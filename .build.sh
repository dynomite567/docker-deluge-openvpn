#!/bin/sh
echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin

archarchitectures="arm arm64 amd64"
platforms=""
DOCKER_TAG="latest"

for arch in $architectures
do
# Build for all architectures and push manifest
  platforms="linux/$arch,$platforms"
done

platforms=${platforms::-1}

buildctl build --frontend dockerfile.v0 \
        --frontend-opt platform=${platforms} \
        --frontend-opt filename=./Dockerfile \
        --exporter image \
        --exporter-opt name=docker.io/$DOCKER_USER/$DOCKER_IMAGE:latest \
        --exporter-opt push=true \
        --local dockerfile=. \
        --local context=.

for arch in $architectures
do
# Build for all architectures and push manifest
  buildctl build --frontend dockerfile.v0 \
      --local dockerfile=. \
      --local context=. \
      --exporter image \
      --exporter-opt name=docker.io/$DOCKER_USER/$DOCKER_IMAGE:latest \
      --exporter-opt push=true \
      --frontend-opt platform=linux/$arch \
      --frontend-opt filename=./Dockerfile &
done
