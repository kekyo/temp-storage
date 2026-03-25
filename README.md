# nginx + WebDAV temporary container

Light-weight WebDAV temporary storage server, intended for use as artifact storage for GitHub Actions.

For the Japanese version, see [README_ja.md](./README_ja.md).

## What is this?

This repository contains a simple storage container definition based on `nginx + WebDAV + autoindex`.

The main use case is storing intermediate artifacts over HTTP from systems such as GitHub Actions while still allowing humans to inspect directory listings in a browser.

## Overview

- Base image: `nginx:1.27-alpine`
- Authentication: HTTP Basic authentication
- Upload: `PUT`
- Download: `GET`
- Delete: `DELETE`
- Directory creation: `MKCOL`
- Directory listing: standard Nginx `autoindex`
- Storage path inside the container: `/var/lib/webdav` (configurable at startup)
- Listen port: `8080` (configurable at startup)

---

## Starting the container

You need `docker` or a compatible container runtime.
The published image name is `docker.io/kekyo/nginx-webdav-temporary` [(docker.io page)](https://hub.docker.com/r/kekyo/nginx-webdav-temporary).

Pull the latest image:

```bash
docker pull docker.io/kekyo/nginx-webdav-temporary:latest
```

Run it with Docker:

```bash
docker run -d \
  --name nginx-webdav-temporary \
  -p 8080:8080 \
  -e WEBDAV_USERNAME=storage-user \
  -e WEBDAV_PASSWORD=storage-pass \
  -v "$(pwd)/data:/var/lib/webdav" \
  docker.io/kekyo/nginx-webdav-temporary:latest
```

If you want to delete all existing files under `/var/lib/webdav` on startup, set `WEBDAV_CLEAR_STORAGE_ON_STARTUP=true`.

```bash
docker run -d \
  --name nginx-webdav-temporary \
  -p 8080:8080 \
  -e WEBDAV_USERNAME=storage-user \
  -e WEBDAV_PASSWORD=storage-pass \
  -e WEBDAV_CLEAR_STORAGE_ON_STARTUP=true \
  -v "$(pwd)/data:/var/lib/webdav" \
  docker.io/kekyo/nginx-webdav-temporary:latest
```

When this option is enabled, everything under the storage root is removed during container startup, while the storage root directory itself is kept.

---

## Usage

The examples below assume the following environment variables:

```bash
export WEBDAV_URL="http://127.0.0.1:8080"
export WEBDAV_USER="storage-user"
export WEBDAV_PASS="storage-pass"
```

### Show a directory listing

Open it in a browser or use `curl`:

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" "${WEBDAV_URL}/"
```

For a subdirectory listing, add a trailing slash:

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" "${WEBDAV_URL}/runs/run-1/job-1/"
```

### Upload a file

Files are stored using `PUT`. Intermediate directories are created automatically even for deep paths.

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
  -T ./artifact.tgz \
  "${WEBDAV_URL}/runs/run-1/job-1/artifact.tgz"
```

### Download a file

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
  -o ./artifact.tgz \
  "${WEBDAV_URL}/runs/run-1/job-1/artifact.tgz"
```

### Delete a file

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
  -X DELETE \
  "${WEBDAV_URL}/runs/run-1/job-1/artifact.tgz"
```

### Create an empty directory

If needed, you can also use `MKCOL`:

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
  -X MKCOL \
  "${WEBDAV_URL}/runs/run-2/"
```

## Example usage from GitHub Actions

```yaml
steps:
  - name: Upload artifact
    env:
      WEBDAV_URL: ${{ secrets.WEBDAV_URL }}
      WEBDAV_USER: ${{ secrets.WEBDAV_USER }}
      WEBDAV_PASS: ${{ secrets.WEBDAV_PASS }}
    run: |
      curl -fsS -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
        -T artifact.tgz \
        "${WEBDAV_URL}/runs/${GITHUB_RUN_ID}/${GITHUB_JOB}/artifact.tgz"

  - name: Download artifact
    env:
      WEBDAV_URL: ${{ secrets.WEBDAV_URL }}
      WEBDAV_USER: ${{ secrets.WEBDAV_USER }}
      WEBDAV_PASS: ${{ secrets.WEBDAV_PASS }}
    run: |
      curl -fsS -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
        -o artifact.tgz \
        "${WEBDAV_URL}/runs/${GITHUB_RUN_ID}/${GITHUB_JOB}/artifact.tgz"
```

## Permission notes

This image uses slightly stronger permission settings so that bind-mounted storage is easier to use both in the current rootless Podman environment and in normal Docker usage.

- Nginx workers run as `root` inside the container.
- When you use Docker with a bind mount, created files may therefore appear as `root:root` on the host.
- In rootless Podman, ownership may appear as mapped subuid/subgid values depending on your environment.
- If host-side ownership matters, prefer a named volume, or prepare the bind-mounted directory with permissions that match your operational policy in advance.

The startup helper script also applies `chmod -R a+rwX` to `/var/lib/webdav` and `/var/lib/nginx/body`, so the mounted storage location stays writable.

## Operational notes

- This uses Basic authentication, so you should always terminate TLS in front of it in production.
- Directory listing is intended for human inspection. For machine-driven workflows, deterministic paths are more reliable.
- This is not object storage. Cleanup and retention must be handled separately.
- The current size limit is `1g`. If you need to change it, update [nginx.conf](./nginx.conf).

The current Nginx configuration includes:

- `client_max_body_size 1g`
- `create_full_put_path on`
- `min_delete_depth 2`
- `autoindex on`
- `autoindex_format html`

Because `min_delete_depth` is set to `2`, paths that are too shallow cannot be deleted.

---

## Integration with systemd

You can control the container with systemd by placing the following file:

`/etc/systemd/system/container-nginx-webdav-temporary.service`:

```ini
[Unit]
Description=Podman container-nginx-webdav-temporary.service
Documentation=man:podman-generate-systemd(1)
Wants=network-online.target
After=network-online.target
RequiresMountsFor=%t/containers

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=/bin/rm -f %t/%n.ctr-id
ExecStart=/usr/bin/podman run --cidfile=%t/%n.ctr-id --cgroups=no-conmon --rm --sdnotify=conmon --replace -p 8080:8080 -e WEBDAV_USERNAME=*************** -e WEBDAV_PASSWORD=*************** -e WEBDAV_CLEAR_STORAGE_ON_STARTUP=true -v /storage0/temp_artifacts:/var/lib/webdav -d --name nginx-webdav-temporary nginx-webdav-temporary:test
ExecStop=/usr/bin/podman stop --ignore --cidfile=%t/%n.ctr-id
ExecStopPost=/usr/bin/podman rm -f --ignore --cidfile=%t/%n.ctr-id
Type=notify
NotifyAccess=all

[Install]
WantedBy=default.target
```

You can also place `/etc/systemd/system/container-nginx-webdav-temporary.timer` to restart it every day:

```ini
[Unit]
Description=Reset container

[Timer]
OnCalendar=03:00
Persistent=false

[Install]
WantedBy=timers.target
```

Because `WEBDAV_CLEAR_STORAGE_ON_STARTUP=true` is specified, the storage is deleted and cleaned up on every restart.
Of course, you can remove that option if you want persistence instead.

Enable the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable container-nginx-webdav-temporary
sudo systemctl start container-nginx-webdav-temporary
```

---

## Building from source

Build environment:

- `podman`
- `curl`
- [`screw-up-native`](https://github.com/kekyo/screw-up-native)

Build locally with Podman:

```bash
make build
```

The default local image name is:

```text
localhost/nginx-webdav-temporary:test
```

Print the version calculated from `screw-up format`:

```bash
make print-version
```

Build a local multi-arch manifest for `linux/amd64` and `linux/arm64`:

```bash
make build-multiarch
```

Push the multi-arch image to Docker Hub:

```bash
podman login docker.io
make push-multiarch
```

By default, `make push-multiarch` pushes to:

- `docker.io/kekyo/nginx-webdav-temporary:{version}`
- `docker.io/kekyo/nginx-webdav-temporary:latest`

Here, `{version}` is the result of `printf '{version}\n' | screw-up format`.

## Verification

Run the automated test with:

```bash
make test
```

This test verifies:

- image build
- container startup
- authenticated directory listing
- preserving pre-existing files on normal startup
- deleting pre-existing files when `WEBDAV_CLEAR_STORAGE_ON_STARTUP=true`
- `PUT`
- listing after upload
- `GET`
- `DELETE`
- `401` on unauthenticated access
- `404` after deletion

## License

MIT.
