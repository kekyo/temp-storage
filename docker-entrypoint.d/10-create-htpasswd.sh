#!/bin/sh
set -eu

if [ -z "${WEBDAV_USERNAME:-}" ]; then
    echo "WEBDAV_USERNAME is required" >&2
    exit 1
fi

if [ -z "${WEBDAV_PASSWORD:-}" ]; then
    echo "WEBDAV_PASSWORD is required" >&2
    exit 1
fi

htpasswd -bc /etc/nginx/htpasswd "$WEBDAV_USERNAME" "$WEBDAV_PASSWORD" >/dev/null
