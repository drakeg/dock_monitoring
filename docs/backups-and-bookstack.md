# Backups and knowledge base

## Encrypted backups (Restic)

Restic provides encrypted, deduplicated snapshots. This script takes logical dumps of
Request Tracker's PostgreSQL and Uptime Kuma's MariaDB databases, then backs up
application Docker volumes and configuration. It does **not** back up raw live
database volumes. The script never deletes application volumes.

1. Choose a backup destination on a **separate mounted disk** (example: `/mnt/backups/dock-monitoring`).
2. Create a strong Restic password file outside the repository and keep a separate
   offline copy. For example:
   ```bash
   sudo install -d -m 700 /mnt/backups/dock-monitoring
   openssl rand -base64 48 | sudo tee /mnt/backups/dock-monitoring/restic-password >/dev/null
   sudo chmod 600 /mnt/backups/dock-monitoring/restic-password
   ```
3. Run:
   ```bash
   sudo BACKUP_DIR=/mnt/backups/dock-monitoring bash scripts/backup.sh
   ```
4. Verify the Restic snapshot and practice restoring to a **separate** test environment.
   For unattended daily backups, schedule this script with a systemd timer or cron
   only after the initial backup and restore test succeeds.

**Important:** A backup stored on the same host is not sufficient protection.
Copy or replicate the encrypted Restic repository to independent/offsite storage.
Keep the repository password safe: losing it makes backups unrecoverable.
Do not expose the password file through Git or web services. Backup archives
include `.env` and may contain credentials; they are encrypted in Restic.

This script is a starting point for this stack, not a backup of every Docker
volume on the host. It deliberately includes known application volumes.
It does not automatically cover arbitrary new services; extend the list when
adding services. Backups are not proven recoverable until a restore is tested.

## BookStack knowledge base

BookStack is an open-source documentation/wiki application with a
Books → Chapters → Pages organization.

The knowledge base is **opt-in** and isolated from the main Compose deployment.
It has its own MariaDB database and two persistent volumes.

Add these to your private `.env` (never commit actual secrets):

```dotenv
BOOKSTACK_PORT=6875
BOOKSTACK_APP_URL=http://localhost:6875
BOOKSTACK_DB_PASSWORD=replace-with-strong-unique-password
BOOKSTACK_DB_ROOT_PASSWORD=replace-with-another-strong-unique-password
BOOKSTACK_APP_KEY=base64:replace-with-generated-base64-key
```

Generate the application key with:
```bash
printf 'base64:%s\n' "$(openssl rand -base64 32 | tr -d '\n')"
```

Start the main stack first (to create its shared `proxy` network), then:
```bash
docker compose -f compose.bookstack.yml up -d
```

Open the URL in `BOOKSTACK_APP_URL` (replace localhost with the server's
reachable hostname/IP for remote use). Change the initial BookStack
administrator credentials immediately. For access from other machines,
`BOOKSTACK_APP_URL` must match the URL users visit.

Backups include BookStack's app volume and a logical dump of its MariaDB
database **when BookStack is running**. The application is not exposed
through the primary Traefik router by default; published port access should
be restricted to trusted LAN/VPN users, not the public internet.
