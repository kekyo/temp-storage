#!/bin/sh
set -eu

case "${WEBDAV_CLEAR_STORAGE_ON_STARTUP:-false}" in
    true|TRUE|1|yes|YES)
        find /var/lib/webdav -mindepth 1 -delete
        ;;
esac
