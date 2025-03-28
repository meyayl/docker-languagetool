SHELL=/bin/bash

all: docker_build docker_compose

docker_build:
	@echo "Building container"
	@sudo docker build -t meyay/languagetool:latest -f Dockerfile.fasttext .
docker_compose:
	@echo "Starting container"
	@docker compose up -d

