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
# --delete-untagged is required, not optional: without it, garbage-collect only
# sweeps blobs with zero manifest references, but leaves untagged manifests
# (and everything they reference) on disk indefinitely -- which is exactly the
# state every deleted tag is in after the Jenkins prune stage runs. Confirmed
# by testing: a plain run left an untagged image's blobs and manifest fully
# intact, reporting "0 manifests eligible for deletion".
docker run --rm -v "$VOLUME:$VOLUME" "$IMAGE" garbage-collect --delete-untagged /etc/docker/registry/config.yml

echo "$(date -Iseconds) Restarting $CONTAINER..."
docker start "$CONTAINER" >/dev/null

echo "$(date -Iseconds) Done."
