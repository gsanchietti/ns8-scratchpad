#!/bin/bash

set -e

container=$(buildah from scratch)

buildah copy ${container} agent /agent
buildah copy ${container} cplane /cplane
buildah copy ${container} dplane /dplane
buildah config --entrypoint=/ ${container}
buildah commit ${container} control-plane

echo
echo "Access DigitalOcean control panel and download docker-config.json file from Container Registry."
echo "Then publish the image with:"
echo
echo " export REGISTRY_AUTH_FILE=path-to/docker-config.json"
echo " buildah push control-plane docker://ghcr.io/nethserver/control-plane:latest"
