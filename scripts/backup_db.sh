#!/usr/bin/env bash
# Daily database backup for the production stack. Keeps 14 days.
# Cron (as the deploy user):  30 2 * * * /opt/micro_bargain/scripts/backup_db.sh >> /var/log/mb_backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
mkdir -p "$BACKUP_DIR"
STAMP="$(date +%Y%m%d_%H%M)"
docker compose -f docker-compose.prod.yml exec -T db \
  sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' > "$BACKUP_DIR/micro_bargain_$STAMP.dump"
find "$BACKUP_DIR" -name 'micro_bargain_*.dump' -mtime +14 -delete
echo "Backup written: $BACKUP_DIR/micro_bargain_$STAMP.dump"
# Restore: docker compose -f docker-compose.prod.yml exec -T db pg_restore -U micro_bargain -d micro_bargain --clean < FILE.dump
