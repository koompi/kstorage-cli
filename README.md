# KStorage CLI

CLI tool for managing files on KConsole Object Storage. Upload, download, list, delete files, and automate database backups directly to cloud storage.

## Installation

Install `kstorage` to `/usr/local/bin` using this one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/koompi/kstorage-cli/master/install.sh | bash
```

Alternatively, download manually and make it executable:

```bash
chmod +x kstorage
# Move it to your PATH
sudo mv kstorage /usr/local/bin/kstorage
```

## Setup

Save your API key (stored in `~/.config/kstorage/config`, file permission `600`):

```bash
kstorage auth sk_your_bucket_api_key_here
```

## Dependencies

Always required:

| Tool | Install |
|------|---------|
| `curl` | `sudo apt install curl` |
| `jq` | `sudo apt install jq` |
| `file` | `sudo apt install file` |

Optional:

| Tool | Install | Used by |
|------|---------|---------|
| `mongodump` / `mongorestore` | `sudo apt install mongodb-database-tools` | `db backup/restore --mongo` |
| `pg_dump` / `psql` | `sudo apt install postgresql-client` | `db backup/restore --postgres` |
| `mysqldump` / `mysql` | `sudo apt install mysql-client` | `db backup/restore --mysql` |
| `gpg` | `sudo apt install gnupg` | Encrypted backups (`db backup --encrypt`) |
| `fzf` | `sudo apt install fzf` | Interactive restore picker (optional, falls back to numbered list) |

Missing tools are detected automatically before running any command, with install instructions shown for each missing tool.

---

## Commands

### auth

Save the bucket API key so you don't have to pass it every time. Key is stored at `~/.config/kstorage/config`.

```bash
kstorage auth sk_your_key_here
kstorage show-key    # print current saved key
```

---

### upload

Upload any file to storage. Default is private; use `--public` for public CDN access.

```bash
# Upload as private (default)
kstorage upload ./photo.png

# Upload as public (CDN link returned)
kstorage upload --public ./photo.png

# Custom filename
kstorage upload ./local-file.txt "remote-name.txt"
kstorage upload --public ./photo.png "banner.png"
```

**Duplicate handling**: If a file with the same name already exists on storage, you'll be prompted:

```
File 'photo.png' already exists (id: 69ba86...).
  [o]verwrite / [r]ename / [c]ancel?
```

- **Overwrite**: Deletes the old file, uploads the new one.
- **Rename**: Auto-appends `_1`, `_2`, etc. (e.g. `photo_1.png`).
- **Cancel**: Exits without doing anything.

---

### list

List all objects in the bucket with filtering and search.

```bash
# Default: first 100 items
kstorage list

# Fetch ALL pages
kstorage list --all

# Server-side search
kstorage list "screenshot"

# Filter by visibility
kstorage list --public
kstorage list --private

# Filter by file extension
kstorage list --ext png
kstorage list --ext gz

# Regex match on filename
kstorage list --match 'photo_\d+'
kstorage list --match '^stadiumx'

# Combine filters
kstorage list --public --ext png --match 'banner'
kstorage list --all --private --match 'backup'

# Raw JSON output
kstorage list --json
```

Output format: `filename  size  visibility  objectId`

```
stadiumx-db-2026-03-18_020000.mongo.gz  1048576B  private  69ba86f4d0ac63b3cd48d787
photo.png                                2048B     public   65d123abc456def789012345
--- Showing 2 / 15
```

---

### url

Get a temporary access URL for a private file. Accepts either a filename or objectId.

```bash
kstorage url stadiumx-db-2026-03-18_020000.mongo.gz
kstorage url 69ba86f4d0ac63b3cd48d787
```

Output: a pre-signed URL that expires after 10 minutes (default).

---

### delete

Delete a file by filename or objectId.

```bash
kstorage delete photo.png
kstorage delete 69ba86f4d0ac63b3cd48d787
```

---

## Database Backup & Restore

### How it works

`kstorage db backup` dumps a database, compresses it, uploads to storage, and optionally schedules automatic backups via cron.

`kstorage db restore` lists available backups (via `fzf` if installed, or numbered list), lets you pick one, downloads it, and restores to your target database.

### Backup flow

```
1. Validate arguments (--mongo/--postgres/--mysql/--mariadb, name, --uri)
2. Check required tools exist (mongodump/pg_dump/mysqldump, curl, jq)
3. If --uri not provided, prompt for it interactively
4. Dump database using the native tool with --gzip
5.        - Mongo: mongodump --archive --gzip (single-file streaming archive,
6.          parallel collection dump via --numParallelCollections=4)
7.        - Postgres/MySQL/MariaDB: dump output piped through gzip
8. (optional) Encrypt the archive with gpg AES-256 if --encrypt is set
9. Upload the (compressed, maybe encrypted) archive to storage
10. Clean up old backups beyond --keep limit (default: 7)
11. Prompt to schedule cron job
```

### Usage

```bash
# MongoDB
kstorage db backup stadiumx --mongo --uri 'mongodb://user:pass@host:27017/stadiumx'

# PostgreSQL
kstorage db backup weteka --postgres --uri 'postgresql://user:pass@host:5432/weteka'

# MySQL
kstorage db backup myapp --mysql --uri 'mysql://user:pass@host:3306/myapp'

# MariaDB
kstorage db backup myapp --mariadb --uri 'mariadb://user:pass@host:3306/myapp'

# Omit --uri to be prompted interactively
kstorage db backup stadiumx --mongo
# > mongo URI (mongodb://user:pass@host:27017): █

# Specify database name separately (if not in URI)
kstorage db backup myapp --mongo --uri 'mongodb://localhost:27017' --db myapp

# Keep only last 3 backups (default: 7)
kstorage db backup stadiumx --mongo --uri '...' --keep 3

# Upload as public (default: private)
kstorage db backup stadiumx --mongo --uri '...' --public

# Dry run - see what would happen without doing it
kstorage db backup stadiumx --mongo --uri '...' --dry-run
```

**Archive naming**: `<name>-db-<timestamp>.<type>.gz` (encrypted backups add `.gpg`)

Examples:
- `stadiumx-db-2026-03-18_020000.mongo.gz`
- `weteka-db-2026-03-18_020000.postgres.gz`
- `myapp-db-2026-03-18_020000.mysql.gz`
- `myapp-db-2026-03-18_020000.mariadb.gz`
- `stadiumx-db-2026-03-18_020000.mongo.gz.gpg` _(encrypted)_

---

### Encryption (optional)

> **Opt-in and backwards compatible.** Encryption is off unless you pass the new
> `--encrypt` / `--password` / `--password-file` argument. **Existing backups and
> cron jobs that don't use these flags keep working exactly as before** — they
> still produce plain `.gz` archives. Restore transparently handles both: old
> unencrypted `.gz` backups and new encrypted `.gz.gpg` backups show up in the
> same picker, and only `.gpg` files trigger a password prompt.

By default, backups are uploaded compressed but **unencrypted** — the plaintext
dump lives in cloud storage as-is. Add `--encrypt` to encrypt the archive
client-side with **gpg symmetric AES-256** _before_ it leaves the machine, so
storage (and anyone holding the API key) only ever sees ciphertext.

The password is all that's needed to decrypt. There's no keypair to manage, and
the file is portable — you can hand someone the `.gpg` file plus the password
and they can open it with plain `gpg`, with or without kstorage.

```bash
# Prompt for a password interactively (asks twice to confirm)
kstorage db backup stadiumx --mongo --uri '...' --encrypt

# Pass the password directly (note: visible in `ps` — prefer the file form)
kstorage db backup stadiumx --mongo --uri '...' --password 'my-secret'

# Read the password from a file (best for scripts and cron)
kstorage db backup stadiumx --mongo --uri '...' --password-file ~/.kstorage.pass

# Or via environment variable
KSTORAGE_BACKUP_PASSWORD='my-secret' kstorage db backup stadiumx --mongo --uri '...' --encrypt
```

**Password sources**, in priority order: `--password-file` → `KSTORAGE_BACKUP_PASSWORD`
env → `--password` → interactive prompt.

Restore auto-detects encrypted (`.gpg`) backups and asks for the password (or
takes it from `--password` / `--password-file` / the env var):

```bash
kstorage db restore stadiumx --mongo --drop --password-file ~/.kstorage.pass
```

**Decrypt by hand** (no kstorage needed):

```bash
gpg -d -o backup.mongo.gz stadiumx-db-2026-03-18_020000.mongo.gz.gpg
# then restore the .gz with mongorestore/psql/mysql as usual
```

> ⚠️ **Key custody**: lose the password and the backup is unrecoverable — that's
> the whole point. Store it somewhere safe and separate from the backups, and
> verify you can decrypt a backup before relying on it.

---

### Restore flow

```
1. Validate arguments (db type, name)
2. Check required tools (mongorestore/psql/mysql, curl, jq)
3. Fetch all backups matching "<name>-db-*.<type>.gz" from storage
4. Display backup picker:
   - If fzf installed: interactive fuzzy finder
   - Otherwise: numbered list with prompt
5. Ask restore target:
   - [1] localhost (default URI for the db type)
   - [2] custom URI (prompted)
   - Or pass --uri to skip the prompt
6. [1/3] Download backup via pre-signed URL
7. [2/3] Restore using the native tool (mongorestore / psql / mysql)
8. [3/3] Clean up temp files
```

### Usage

```bash
# Interactive - picks backup via fzf/list, then asks restore mode and target
kstorage db restore stadiumx --mongo

# Clean restore (recommended) - drops existing data, restores from backup
kstorage db restore stadiumx --mongo --drop

# Restore to specific target (skip target prompt)
kstorage db restore stadiumx --mongo --uri 'mongodb://localhost:27017/stadiumx'

# Clean restore to specific target
kstorage db restore stadiumx --mongo --drop --uri 'mongodb://localhost:27017/stadiumx'

# Restore to a remote server
kstorage db restore weteka --postgres --uri 'postgresql://admin:pass@prod-host:5432/weteka'
```

**Restore modes:**

| Mode | Flag | Behavior |
|------|------|----------|
| Clean (recommended) | `--drop` | Drops existing collections/tables, then restores. Gives you an exact copy of the backup. |
| Merge | _(default if no prompt)_ | Only inserts new documents. Skips duplicates (E11000 errors for Mongo). |

If `--drop` is not passed on the command line, you'll be prompted:

```
Restore mode:
  [1] Clean restore (--drop) — drops existing data, restores from backup (recommended)
  [2] Merge — only insert new documents, skip duplicates
Choice [1/2]:
```

Clean restore requires confirmation:

```
⚠  WARNING: This will DROP all existing data in the target database
   and replace it with the backup. This cannot be undone.

Type 'yes' to confirm:
```

---

### Cron (Automatic Backups)

After every successful `db backup`, you'll be prompted:

```
Schedule automatic backups?
  [1] Every night
  [2] Twice a day (every 12 hours)
  [3] Every 6 hours
  [4] Every week (Sunday)
  [5] Weekdays only (Mon-Fri)
  [6] Custom cron expression
  [7] Skip
Choice [1-7]:
```

For most options, you'll then pick a time:

```
What time?
  [1]  12:00 AM (midnight)
  [2]   1:00 AM
  [3]   2:00 AM (recommended)
  [4]   3:00 AM
  [5]   4:00 AM
  [6]   5:00 AM
  [7]   6:00 AM
  [8]  12:00 PM (noon)
  [9]   6:00 PM
  [10]  9:00 PM
Choice [1-10] (default: 3):
```

**Option 6** (Custom) lets you enter a raw cron expression for advanced scheduling.

Then asks where to install:

```
Install as sudo user? [y/N]:
```

- **Yes**: Writes to `/etc/cron.d/kstorage-backup-<name>` (system-wide, runs as root)
- **No**: Adds to current user's crontab (view with `crontab -l`)

**Important**: The cron job saves your `--uri` (including credentials) in plain text in the crontab. Make sure the crontab file permissions are restrictive. For the `/etc/cron.d/` file, permissions are set to `644` (readable by all, writable by root). For user crontab, it's managed by the system.

**Encrypted backups in cron**: if you used `--encrypt`, the cron job needs the password without a prompt. kstorage saves it to `~/.config/kstorage/backup-<name>.pass` (`chmod 600`) and references it via `--password-file` in the cron line — the password itself is never written into the crontab. Provide your own file with `--password-file` to reuse an existing one.

**Removing a cron job**:
```bash
# System-wide cron
sudo rm /etc/cron.d/kstorage-backup-stadiumx

# User crontab - edit and remove the line tagged # kstorage:stadiumx
crontab -e
```

---

## Configuration

| File | Description |
|------|-------------|
| `~/.config/kstorage/config` | Saved API key (`key=sk_...`) |
| `~/.config/kstorage/backup-<name>.pass` | Saved backup password for encrypted cron jobs (`chmod 600`) |
| `/etc/cron.d/kstorage-backup-<name>` | System-wide cron jobs |
| User crontab | User-level cron jobs (tagged with `# kstorage:<name>`) |

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `KSTORAGE_BASE_URL` | Override API base URL | `https://api-kconsole.koompi.cloud` |
| `KSTORAGE_BACKUP_PASSWORD` | Encryption/decryption password for `db backup --encrypt` / `db restore` | _(none)_ |

---

## API Reference

All requests use the KConsole Object Storage API:

| Action | Method | Endpoint |
|--------|--------|----------|
| Get upload token | POST | `/api/storage/upload-token` |
| Confirm upload | POST | `/api/storage/complete` |
| Get pre-signed URL | GET | `/api/storage/objects/{id}/url` |
| List objects | GET | `/api/storage/objects` |
| Delete object | DELETE | `/api/storage/objects/{id}` |

All requests include `x-api-key: <bucket_key>` header. Files are uploaded to Cloudflare R2 via pre-signed PUT URLs.
