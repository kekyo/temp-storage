# nginx + WebDAV temporary container

Light-weight temporary webdav storage server, designed for GitHub Actions artifacts.

---

For the Japanese version, see [README_ja.md](./README_ja.md).

## What is this?

This directory contains a simple storage container definition based on `nginx + WebDAV + autoindex`.

The intended use case is to store intermediate artifacts over HTTP from systems such as GitHub Actions, while still allowing humans to inspect directory listings in a browser.

## Overview

- Base image: `nginx:1.27-alpine`
- Authentication: HTTP Basic authentication
- Upload: `PUT`
- Download: `GET`
- Delete: `DELETE`
- Directory creation: `MKCOL`
- Directory listing: standard Nginx `autoindex`
- Storage path inside the container: `/var/lib/webdav`
- Listen port: `8080`

The current configuration includes the following Nginx settings:

- `client_max_body_size 1g`
- `create_full_put_path on`
- `min_delete_depth 2`
- `autoindex on`
- `autoindex_format html`

Because `min_delete_depth` is set to `2`, paths that are too shallow cannot be deleted.

## Requirements

- `podman`
- `curl`
- Permission to create a persistent host-side directory

## Setup

### 1. Build the image

```bash
make build
```

If you want to specify the image name explicitly:

```bash
podman build -t temp-storage-nginx-webdav:local .
```

### 2. Create a data directory

```bash
mkdir -p ./data
```

### 3. Run the container

```bash
podman run -d \
  --name temp-storage-nginx-webdav \
  -p 8080:8080 \
  -e WEBDAV_USERNAME=storage-user \
  -e WEBDAV_PASSWORD=storage-pass \
  -v "$(pwd)/data:/var/lib/webdav" \
  temp-storage-nginx-webdav:test
```

`WEBDAV_USERNAME` and `WEBDAV_PASSWORD` are required. The container exits during startup if either one is missing.

If you are using a SELinux-enabled environment, add `:Z` to the bind mount as needed:

```bash
-v "$(pwd)/data:/var/lib/webdav:Z"
```

---

## Usage (Actions runner/client site)

The examples below assume the following environment variables:

```bash
export WEBDAV_URL="http://127.0.0.1:8080"
export WEBDAV_USER="storage-user"
export WEBDAV_PASS="storage-pass"
```

### Show a directory listing

Open the URL in a browser or use `curl`:

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" "${WEBDAV_URL}/"
```

For a subdirectory listing, include a trailing slash:

```bash
curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" "${WEBDAV_URL}/runs/run-1/job-1/"
```

### Upload a file

Files are stored with `PUT`. Intermediate directories are created automatically for deep paths.

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

If needed, you can use `MKCOL`:

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

## Operational notes

- This uses Basic authentication, so you should terminate TLS in front of it in production.
- Directory listing is intended for human inspection. For machine-driven workflows, deterministic paths are more reliable.
- This is not object storage. Cleanup and retention policies need to be handled separately.
- The current size limit is `1g`. If you need to change it, update [nginx.conf](./nginx.conf).

---

## Verification

Run the automated verification with:

```bash
make test
```

This test covers:

- image build
- container startup
- authenticated directory listing
- `PUT`
- listing after upload
- `GET`
- `DELETE`
- `401` for unauthenticated access
- `404` after deletion

---

## License

Under MIT.
