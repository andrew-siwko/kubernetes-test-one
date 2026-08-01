#!/bin/sh
#
# Reclaims disk space from blobs orphaned by manifest deletions -- the
# Jenkins "Prune Old Registry Tags" stage only unlinks manifests via the
# registry HTTP API and never touches blob storage, so this is what
# actually frees space.
#
# Runs on the registry host itself (kregistry), via cron -- not from
# Jenkins. The registry is stopped for the duration: garbage-collect must
# not run concurrently with a push, since a blob uploaded mid-run can look
# unreferenced and get deleted, corrupting the image it belongs to.
#
# This is the canonical copy; the copy actually invoked by cron on
# kregistry must be updated to match if this changes.

set -eu

CONTAINER=docker-registry
IMAGE=registry:2
VOLUME=/var/lib/registry

echo "$(date -Iseconds) Stopping $CONTAINER for garbage collection..."
docker stop "$CONTAINER" >/dev/null

echo "$(date -Iseconds) Running garbage-collect..."
docker run --rm -v "$VOLUME:$VOLUME" "$IMAGE" garbage-collect /etc/docker/registry/config.yml

echo "$(date -Iseconds) Restarting $CONTAINER..."
docker start "$CONTAINER" >/dev/null

echo "$(date -Iseconds) Done."
