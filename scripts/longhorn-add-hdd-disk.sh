#!/usr/bin/env bash
#
# One-time, manual. Turns the 200G "scsi1" data disk that
# terraform-proxmox-test/06-servers-knode.tf adds to knode09-12 (backed by
# proxbox-1's HDD ZFS pool "pool1") into a second Longhorn disk on each node.
#
# Per node:
#   1. Formats the disk XFS -- only if it has no filesystem yet. The disk is
#      found by its stable Proxmox ID (drive-scsi1), never by sdX letter.
#   2. Mounts it at /var/lib/longhorn-hdd, persisted in fstab by UUID with
#      nofail, so a missing disk can't block boot.
#   3. Adds it to the node's Longhorn disk list as "hdd" with tag "hdd".
#      The existing default disk on the m2 SSD is left alone.
#
# Safe to re-run: each step is skipped if already done.
#
# Not wired into Jenkins, same as longhorn-node-prep.sh: host-level work over
# ssh lives in scripts/ and is run by hand.

set -euo pipefail

NODES=(knode09 knode10 knode11 knode12)
MOUNT=/var/lib/longhorn-hdd
DEV_ID=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
# Longhorn won't schedule into this much of the disk; leaves room for XFS and
# replica rebuild scratch space.
RESERVED_BYTES=$((20 * 1024 * 1024 * 1024))

for node in "${NODES[@]}"; do
  echo "=== $node ==="
  # knode09-12 are cloud-init VMs: root login is refused, use asiwko + sudo.
  ssh -o ConnectTimeout=5 asiwko@"$node" "sudo MOUNT=$MOUNT DEV_ID=$DEV_ID bash -s" <<'EOF'
set -euo pipefail

if [ ! -b "$DEV_ID" ]; then
  echo "ERROR: $DEV_ID not present -- has the terraform change been applied and the disk hot-plugged?" >&2
  exit 1
fi
dev=$(readlink -f "$DEV_ID")

if [ -n "$(lsblk -no PARTTYPE,FSTYPE "$dev" | tr -d '[:space:]')" ] || [ "$(lsblk -no NAME "$dev" | wc -l)" -gt 1 ]; then
  echo "$dev already has a filesystem or partitions; not formatting"
else
  echo "formatting $dev as XFS"
  mkfs.xfs -L longhorn-hdd "$dev"
fi

uuid=$(blkid -s UUID -o value "$dev")
mkdir -p "$MOUNT"
if ! grep -q "UUID=$uuid" /etc/fstab; then
  echo "UUID=$uuid $MOUNT xfs defaults,nofail 0 0" >> /etc/fstab
  systemctl daemon-reload
fi
mountpoint -q "$MOUNT" || mount "$MOUNT"
df -h "$MOUNT"
EOF

  if kubectl -n longhorn-system get nodes.longhorn.io "$node" -o jsonpath='{.spec.disks.hdd.path}' | grep -q .; then
    echo "Longhorn disk 'hdd' already registered on $node"
  else
    kubectl -n longhorn-system patch nodes.longhorn.io "$node" --type merge -p "{
      \"spec\": {\"disks\": {\"hdd\": {
        \"path\": \"$MOUNT\",
        \"allowScheduling\": true,
        \"diskType\": \"filesystem\",
        \"storageReserved\": $RESERVED_BYTES,
        \"tags\": [\"hdd\"]
      }}}}"
    echo "registered Longhorn disk 'hdd' on $node"
  fi
done

echo
echo "Check: kubectl -n longhorn-system get nodes.longhorn.io knode09 -o jsonpath='{.status.diskStatus.hdd.conditions}'"
