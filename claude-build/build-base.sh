#!/bin/bash
set -e

IMAGE_NAME="richtt02/claude-base"
TAG="${1:-latest}"

echo "Building base image: ${IMAGE_NAME}:${TAG}"
docker build -f Dockerfile.base -t "${IMAGE_NAME}:${TAG}" .

echo ""
echo "Image built successfully!"
echo ""
echo "To push to Docker Hub:"
echo "  docker login"
echo "  docker push ${IMAGE_NAME}:${TAG}"
echo ""
echo "Or run: ./build-base.sh push"

if [ "$1" == "push" ] || [ "$2" == "push" ]; then
    echo ""
    echo "Pushing to Docker Hub..."
    docker push "${IMAGE_NAME}:${TAG}"
    echo "Push complete!"
fi
