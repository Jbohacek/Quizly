#!/bin/sh
# Nightly backup of the Quizly database (CLAUDE.md §10): one compressed pg_dump per run,
# the newest 14 kept. Runs on the server from cron, see README-deploy.md "Backups":
#
#   30 3 * * * /opt/quizly/backup.sh >> /opt/quizly/backups/backup.log 2>&1
#
# The database credentials stay in the container: pg_dump runs there as its POSTGRES_USER.
set -eu

CONTAINER="${QUIZLY_DB_CONTAINER:-quizly-db-1}"
DIR="${QUIZLY_BACKUP_DIR:-/opt/quizly/backups}"
KEEP="${QUIZLY_BACKUP_KEEP:-14}"

mkdir -p "$DIR"
file="$DIR/quizly-$(date +%Y-%m-%d-%H%M).dump"
tmp="$file.partial"
trap 'rm -f "$tmp"' EXIT

docker exec "$CONTAINER" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' > "$tmp"
if [ ! -s "$tmp" ]; then
  echo "$(date '+%F %T') backup FAILED: empty dump" >&2
  exit 1
fi
mv "$tmp" "$file"

# Keep the newest $KEEP dumps. Counting files (not days) keeps old ones when backups stop working.
ls -1t "$DIR"/quizly-*.dump | tail -n +"$((KEEP + 1))" | while read -r old; do rm -f "$old"; done

echo "$(date '+%F %T') backup ok: $file ($(du -h "$file" | cut -f1))"
