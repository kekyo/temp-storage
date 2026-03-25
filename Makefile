IMAGE_NAME ?= temp-storage-nginx-webdav:test

.PHONY: build test

build:
	podman build -t $(IMAGE_NAME) .

test:
	./tests/test-container.sh $(IMAGE_NAME)
