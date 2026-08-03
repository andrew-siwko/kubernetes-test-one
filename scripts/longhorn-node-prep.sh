#!/usr/bin/env bash
#
# One-time, manual. Installs and enables Longhorn's host-level prerequisites
# on every node that will run its manager/engine DaemonSet. Longhorn's own
# install-prerequisites docs list these as required before volumes will
# actually attach -- confirmed live on this cluster that iscsid is missing
# everywhere, so pods would schedule fine but fail to mount without this.
#
# Must be run BEFORE the Jenkinsfile's "Install Longhorn" stage is ever run
# for the first time, so DaemonSet pods can attach immediately rather than
# schedule-then-fail.
#
# Deliberately excludes orangepizero3 (arm64, only ~7GB free, already
# tainted dedicated=sdr:NoSchedule -- not a Longhorn candidate, no need to
# fight its existing exclusion).
#
# Not wired into Jenkins: this is host-level `ssh root@` package
# installation, outside what Jenkins does in this repo's model (see
# registry-gc.sh for the same pattern -- host prep lives in scripts/, run
# by hand).

set -euo pipefail

NODES=(kcontrol01 knode01 knode02 knode03 knode04 knode05 knode06 knode07 knode08)

for node in "${NODES[@]}"; do
  echo "=== $node ==="
  ssh -o ConnectTimeout=5 root@"$node" 'bash -s' <<'EOF'
set -euo pipefail

if rpm -q iscsi-initiator-utils >/dev/null 2>&1; then
  echo "iscsi-initiator-utils already installed"
else
  echo "installing iscsi-initiator-utils..."
  dnf install -y iscsi-initiator-utils
fi

# Don't clobber an existing IQN if one's already been generated.
if [ ! -s /etc/iscsi/initiatorname.iscsi ]; then
  echo "InitiatorName=$(/sbin/iscsi-iname)" > /etc/iscsi/initiatorname.iscsi
fi

systemctl enable --now iscsid

if ! grep -qs '^iscsi_tcp$' /etc/modules-load.d/*.conf 2>/dev/null; then
  echo iscsi_tcp > /etc/modules-load.d/iscsi_tcp.conf
fi
modprobe iscsi_tcp

# Rest of Longhorn's documented prerequisite list -- cheap to cover now
# (backup/restore and encrypted volumes need these) vs. a future surprise.
rpm -q nfs-utils >/dev/null 2>&1 || dnf install -y nfs-utils
rpm -q cryptsetup >/dev/null 2>&1 || dnf install -y cryptsetup
rpm -q device-mapper >/dev/null 2>&1 || dnf install -y device-mapper

echo "iscsid: $(systemctl is-active iscsid), $(systemctl is-enabled iscsid)"
EOF
  echo
done

echo "Done. All nodes prepped except orangepizero3 (excluded)."
