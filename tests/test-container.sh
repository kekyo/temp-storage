#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${1:-temp-storage-nginx-webdav:test}"
CONTAINER_NAME="temp-storage-nginx-webdav-test"
USERNAME="ci-user"
PASSWORD="ci-pass"
HOST_PLATFORM="$(podman info --format '{{.Host.OS}}/{{.Host.Arch}}')"
STORAGE_DIR="$(mktemp -d)"
WORKDIR="$(mktemp -d)"

cleanup() {
  podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  rm -rf "${STORAGE_DIR}" "${WORKDIR}"
}

trap cleanup EXIT

cleanup

mkdir -p "${STORAGE_DIR}" "${WORKDIR}"

podman build --platform "${HOST_PLATFORM}" -t "${IMAGE_NAME}" .

mkdir -p "${STORAGE_DIR}/preexisting"
printf 'keep me\n' > "${STORAGE_DIR}/preexisting/keep.txt"

podman run -d \
  --name "${CONTAINER_NAME}" \
  -p 127.0.0.1::8080 \
  -e WEBDAV_USERNAME="${USERNAME}" \
  -e WEBDAV_PASSWORD="${PASSWORD}" \
  -v "${STORAGE_DIR}:/var/lib/webdav:Z" \
  "${IMAGE_NAME}" >/dev/null

PORT="$(podman port "${CONTAINER_NAME}" 8080/tcp | sed -E 's#.*:([0-9]+)$#\1#')"
BASE_URL="http://127.0.0.1:${PORT}"

for _ in $(seq 1 30); do
  if curl -fsS -u "${USERNAME}:${PASSWORD}" "${BASE_URL}/" >/dev/null; then
    break
  fi
  sleep 1
done

curl -fsS -u "${USERNAME}:${PASSWORD}" "${BASE_URL}/" | grep -F 'Index of /' >/dev/null
curl -fsS -u "${USERNAME}:${PASSWORD}" "${BASE_URL}/preexisting/" | grep -F 'keep.txt' >/dev/null

cleanup_container_only() {
  podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}

cleanup_container_only

podman run -d \
  --name "${CONTAINER_NAME}" \
  -p 127.0.0.1::8080 \
  -e WEBDAV_USERNAME="${USERNAME}" \
  -e WEBDAV_PASSWORD="${PASSWORD}" \
  -e WEBDAV_CLEAR_STORAGE_ON_STARTUP=true \
  -v "${STORAGE_DIR}:/var/lib/webdav:Z" \
  "${IMAGE_NAME}" >/dev/null

PORT="$(podman port "${CONTAINER_NAME}" 8080/tcp | sed -E 's#.*:([0-9]+)$#\1#')"
BASE_URL="http://127.0.0.1:${PORT}"

for _ in $(seq 1 30); do
  if curl -fsS -u "${USERNAME}:${PASSWORD}" "${BASE_URL}/" >/dev/null; then
    break
  fi
  sleep 1
done

status_code="$(curl -s -o /dev/null -w '%{http_code}' -u "${USERNAME}:${PASSWORD}" "${BASE_URL}/preexisting/keep.txt")"
[ "${status_code}" = "404" ]

printf 'artifact payload\n' > "${WORKDIR}/artifact.txt"

TARGET_PATH="/runs/run-1/job-1/artifact.txt"

curl -fsS \
  -u "${USERNAME}:${PASSWORD}" \
  -T "${WORKDIR}/artifact.txt" \
  "${BASE_URL}${TARGET_PATH}" >/dev/null

curl -fsS -u "${USERNAME}:${PASSWORD}" "${BASE_URL}/runs/run-1/job-1/" | grep -F 'artifact.txt' >/dev/null

curl -fsS \
  -u "${USERNAME}:${PASSWORD}" \
  -o "${WORKDIR}/downloaded.txt" \
  "${BASE_URL}${TARGET_PATH}"

cmp -s "${WORKDIR}/artifact.txt" "${WORKDIR}/downloaded.txt"

status_code="$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/")"
[ "${status_code}" = "401" ]

curl -fsS \
  -u "${USERNAME}:${PASSWORD}" \
  -X DELETE \
  "${BASE_URL}${TARGET_PATH}" >/dev/null

status_code="$(curl -s -o /dev/null -w '%{http_code}' -u "${USERNAME}:${PASSWORD}" "${BASE_URL}${TARGET_PATH}")"
[ "${status_code}" = "404" ]
