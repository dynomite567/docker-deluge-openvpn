#!/bin/sh
docker login --username $DOCKER_USERNAME --password $DOCKER_PASSWORD

architectures="arm amd64"
images=""
platforms=""

for arch in $architectures
do
# Build for all architectures and push manifest
  platforms="linux/$arch,$platforms"
done

platforms=${platforms::-1}


buildctl build --frontend dockerfile.v0 \
        --local dockerfile=. \
        --local context=. \
        --exporter image \
        --exporter-opt name=docker.io/$DOCKER_USERNAME/$DOCKER_IMAGE:latest \
        --exporter-opt push=true \
        --frontend-opt platform=$platforms \
        --frontend-opt filename=./Dockerfile