SHELL=/bin/bash

all: docker_build docker_compose

docker_build:
	@echo "Building container"
	@sudo docker build -t meyay/languagetool:latest -f Dockerfile.fasttext .

docker_build_arm64:
	@echo "Building ARM64 container"
	@sudo docker buildx build --platform linux/arm64 --load -t meyay/languagetool:arm64 .

docker_build_fasttext_arm64:
	@echo "Building ARM64 container with source-built fasttext"
	@sudo docker buildx build --platform linux/arm64 --load -t meyay/languagetool:arm64-fasttext -f Dockerfile.fasttext .

docker_compose:
	@echo "Starting container"
	@docker compose up -d

