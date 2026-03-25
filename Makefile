LOCAL_IMAGE_NAME ?= localhost/nginx-webdav-temporary:test
LOCAL_AMD64_IMAGE_NAME ?= localhost/nginx-webdav-temporary:test-amd64
LOCAL_ARM64_IMAGE_NAME ?= localhost/nginx-webdav-temporary:test-arm64
LOCAL_MANIFEST_NAME ?= localhost/nginx-webdav-temporary:multiarch
PUBLISH_IMAGE_NAME ?= docker.io/kekyo/nginx-webdav-temporary
HOST_PLATFORM ?= $(shell podman info --format '{{.Host.OS}}/{{.Host.Arch}}' 2>/dev/null)

.PHONY: build test print-version build-multiarch push-multiarch

build:
	podman build --platform $(HOST_PLATFORM) -t $(LOCAL_IMAGE_NAME) .

test:
	./tests/test-container.sh $(LOCAL_IMAGE_NAME)

print-version:
	@printf '%s\n' '{version}' | screw-up format

build-multiarch:
	podman manifest rm $(LOCAL_MANIFEST_NAME) >/dev/null 2>&1 || true
	podman manifest create $(LOCAL_MANIFEST_NAME)
	podman build --platform linux/amd64 --manifest $(LOCAL_MANIFEST_NAME) -t $(LOCAL_AMD64_IMAGE_NAME) .
	podman build --platform linux/arm64 --manifest $(LOCAL_MANIFEST_NAME) -t $(LOCAL_ARM64_IMAGE_NAME) .
	podman manifest inspect $(LOCAL_MANIFEST_NAME)

push-multiarch: build-multiarch
	VERSION="$$(printf '%s\n' '{version}' | screw-up format)"; \
	podman manifest push --all $(LOCAL_MANIFEST_NAME) "docker://$(PUBLISH_IMAGE_NAME):$$VERSION"; \
	podman manifest push --all $(LOCAL_MANIFEST_NAME) "docker://$(PUBLISH_IMAGE_NAME):latest"
