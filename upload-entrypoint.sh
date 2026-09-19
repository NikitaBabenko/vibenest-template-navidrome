#!/bin/sh
set -eu

if [ -z "${ADMIN_PASSWORD:-}" ]; then
  echo "ADMIN_PASSWORD is required" >&2
  exit 1
fi

set -- \
  --address 0.0.0.0 \
  --port 80 \
  --baseurl /music-upload \
  --root /srv \
  --database /database/filebrowser.db \
  --config /config/settings.json \
  --disableExec

if [ ! -f /database/filebrowser.db ]; then
  password_hash="$(/bin/filebrowser hash "${ADMIN_PASSWORD}")"
  set -- "$@" --username admin --password "${password_hash}"
else
  /bin/filebrowser \
    --database /database/filebrowser.db \
    --config /config/settings.json \
    users update admin \
    --password "${ADMIN_PASSWORD}" \
    --perm.admin >/dev/null
fi

exec /bin/filebrowser "$@"
