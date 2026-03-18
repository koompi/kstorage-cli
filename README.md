# kstorage

CLI tool for managing files on KConsole Object Storage. Upload, download, list, delete files, and automate database backups directly to cloud storage.

## Setup

```bash
# Make it executable
chmod +x kstorage

# Save your API key (stored in ~/.config/kstorage/config, file permission 600)
./kstorage auth sk_your_bucket_api_key_here
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
| `fzf` | `sudo apt install fzf` | Interactive restore picker (optional, falls back to numbered list) |

Missing tools are detected automatically before running any command, with install instructions shown for each missing tool.

---

## Commands

### auth

Save the bucket API key so you don't have to pass it every time. Key is stored at `~/.config/kstorage/config`.

```bash
./kstorage auth sk_your_key_here
./kstorage show-key    # print current saved key
```

---

### upload

Upload any file to storage. Default is private; use `--public` for public CDN access.

```bash
# Upload as private (default)
./kstorage upload ./photo.png

# Upload as public (CDN link returned)
./kstorage upload --public ./photo.png

# Custom filename
./kstorage upload ./local-file.txt "remote-name.txt"
./kstorage upload --public ./photo.png "banner.png"
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
./kstorage list

# Fetch ALL pages
./kstorage list --all

# Server-side search
./kstorage list "screenshot"

# Filter by visibility
./kstorage list --public
./kstorage list --private

# Filter by file extension
./kstorage list --ext png
./kstorage list --ext gz

# Regex match on filename
./kstorage list --match 'photo_\d+'
./kstorage list --match '^stadiumx'

# Combine filters
./kstorage list --public --ext png --match 'banner'
./kstorage list --all --private --match 'backup'

# Raw JSON output
./kstorage list --json
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
./kstorage url stadiumx-db-2026-03-18_020000.mongo.gz
./kstorage url 69ba86f4d0ac63b3cd48d787
```

Output: a pre-signed URL that expires after 10 minutes (default).

---

### delete

Delete a file by filename or objectId.

```bash
./kstorage delete photo.png
./kstorage delete 69ba86f4d0ac63b3cd48d787
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
4. [1/3] Dump database using the native tool with --gzip
5.        - Mongo: mongodump -> tar.gz archive
6.        - Postgres/MySQL/MariaDB: dump output piped through gzip
7. [2/3] Upload compressed archive to storage
8. [3/3] Clean up old backups beyond --keep limit (default: 7)
9. Prompt to schedule cron job
```

### Usage

```bash
# MongoDB
./kstorage db backup stadiumx --mongo --uri 'mongodb://user:pass@host:27017/stadiumx'

# PostgreSQL
./kstorage db backup weteka --postgres --uri 'postgresql://user:pass@host:5432/weteka'

# MySQL
./kstorage db backup myapp --mysql --uri 'mysql://user:pass@host:3306/myapp'

# MariaDB
./kstorage db backup myapp --mariadb --uri 'mariadb://user:pass@host:3306/myapp'

# Omit --uri to be prompted interactively
./kstorage db backup stadiumx --mongo
# > mongo URI (mongodb://user:pass@host:27017): █

# Specify database name separately (if not in URI)
./kstorage db backup myapp --mongo --uri 'mongodb://localhost:27017' --db myapp

# Keep only last 3 backups (default: 7)
./kstorage db backup stadiumx --mongo --uri '...' --keep 3

# Upload as public (default: private)
./kstorage db backup stadiumx --mongo --uri '...' --public

# Dry run - see what would happen without doing it
./kstorage db backup stadiumx --mongo --uri '...' --dry-run
```

**Archive naming**: `<name>-db-<timestamp>.<type>.gz`

Examples:
- `stadiumx-db-2026-03-18_020000.mongo.gz`
- `weteka-db-2026-03-18_020000.postgres.gz`
- `myapp-db-2026-03-18_020000.mysql.gz`
- `myapp-db-2026-03-18_020000.mariadb.gz`

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
./kstorage db restore stadiumx --mongo

# Clean restore (recommended) - drops existing data, restores from backup
./kstorage db restore stadiumx --mongo --drop

# Restore to specific target (skip target prompt)
./kstorage db restore stadiumx --mongo --uri 'mongodb://localhost:27017/stadiumx'

# Clean restore to specific target
./kstorage db restore stadiumx --mongo --drop --uri 'mongodb://localhost:27017/stadiumx'

# Restore to a remote server
./kstorage db restore weteka --postgres --uri 'postgresql://admin:pass@prod-host:5432/weteka'
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
| `/etc/cron.d/kstorage-backup-<name>` | System-wide cron jobs |
| User crontab | User-level cron jobs (tagged with `# kstorage:<name>`) |

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `KSTORAGE_BASE_URL` | Override API base URL | `https://api-kconsole.koompi.cloud` |

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
