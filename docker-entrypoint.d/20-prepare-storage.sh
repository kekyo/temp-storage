#!/bin/sh
set -eu

mkdir -p /var/lib/webdav /var/lib/nginx/body
chmod -R a+rwX /var/lib/webdav /var/lib/nginx/body
