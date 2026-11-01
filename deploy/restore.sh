#!/bin/sh
# Restores a dump made by backup.sh into the database container, replacing everything in it.
# All or nothing: a failed restore leaves the database as it was.
#
#   1. Portainer → stack quizly → stop the `quizly` container (the API), keep `db` running.
#   2. /opt/quizly/restore.sh /opt/quizly/backups/quizly-2026-11-02-0330.dump
#   3. Start the `quizly` container again.
set -eu

CONTAINER="${QUIZLY_DB_CONTAINER:-quizly-db-1}"
file="${1:-}"

if [ -z "$file" ] || [ ! -s "$file" ]; then
  echo "Usage: $0 <backup.dump>   (no such backup: '$file')" >&2
  exit 1
fi

if [ "${QUIZLY_RESTORE_CONFIRM:-}" != "yes" ]; then
  printf 'Replace the whole database in %s with %s? Type "yes": ' "$CONTAINER" "$file"
  read -r answer
  [ "$answer" = "yes" ] || { echo "Nothing changed."; exit 1; }
fi

docker exec -i "$CONTAINER" sh -c \
  'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --single-transaction' < "$file"

echo "Restored $file into $CONTAINER. Start the quizly container again."
