.PHONY: build push test

DOCKER_IMAGE=vitorosan/openstreetmap-tile-server

build:
	docker build -t ${DOCKER_IMAGE} .

push: build
	docker push ${DOCKER_IMAGE}:latest