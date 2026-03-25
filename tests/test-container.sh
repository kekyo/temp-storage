#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${1:-temp-storage-nginx-webdav:test}"
CONTAINER_NAME="temp-storage-nginx-webdav-test"
USERNAME="ci-user"
PASSWORD="ci-pass"

cleanup() {
  podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}

trap cleanup EXIT

cleanup

podman build -t "${IMAGE_NAME}" .

podman run -d \
  --name "${CONTAINER_NAME}" \
  -p 127.0.0.1::8080 \
  -e WEBDAV_USERNAME="${USERNAME}" \
  -e WEBDAV_PASSWORD="${PASSWORD}" \
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

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"; cleanup' EXIT

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
