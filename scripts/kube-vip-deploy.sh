#!/usr/bin/env bash
#
# One-time, manual. Writes the kube-vip static pod manifest
# (/etc/kubernetes/manifests/kube-vip.yaml) onto every control-plane node.
#
# kube-vip hands out the control-plane VIP (192.168.50.155,
# kcontrol.siwko.org) that the API server itself is reached through, so it
# has to run as a static pod -- each node's kubelet reads the manifest
# straight off local disk, independent of the API server. A DaemonSet can't
# do this: it can't schedule if the API server it depends on isn't up yet.
# kubectl apply can't do this either, for the same reason. See k8s/kube-vip.yaml
# for the full per-node Pod specs this script writes verbatim, and its
# header for the 2026-09-17 incident that found kcontrol02/kcontrol03 running
# without it -- kube-vip already does leader election (plndr-cp-lock lease)
# so it's designed to run on every control-plane node and race for the VIP;
# it just has to actually be there first.
#
# Not wired into Jenkins: this is host-level filesystem writes on specific
# nodes, outside what Jenkins does in this repo's model (see
# longhorn-node-prep.sh / registry-gc.sh for the same pattern -- host prep
# lives in scripts/, run by hand).
#
# Idempotent: overwrites the file with the same content every run. The
# kubelet only restarts the static pod if the content actually changed.
#
# kcontrol01 is a VirtualBox VM (Ubuntu, root SSH, interface enp0s3).
# kcontrol02/kcontrol03 are Proxmox VMs (RHEL, asiwko + sudo, interface eth0).
#
# Learned the hard way on kcontrol02/kcontrol03 (2026-09-18): a fresh
# `kubeadm join` doesn't always generate /etc/kubernetes/super-admin.conf,
# which the manifest below mounts. Writing the manifest before that file
# exists makes kubelet silently create an empty DIRECTORY in its place
# (hostPath with no `type` set doesn't fail on a missing path) -- kube-vip
# then can't read any kubeconfig and crash-loops, and because static pods
# only get a fresh mount when their sandbox is recreated (not on
# `kubectl delete pod`, which just deletes the API mirror object), fixing
# the file afterward isn't enough on its own. So ensure_super_admin_conf
# runs first, before the manifest is ever written, to avoid that ordering
# bug entirely. It generates the file pointed at the node's OWN local IP
# (--apiserver-advertise-address), never the cluster's controlPlaneEndpoint
# (kcontrol.siwko.org, i.e. this same VIP) -- kube-vip depending on the VIP
# to reach the API server it does its own leader election through would be
# exactly backwards for a failover target.

set -euo pipefail

ensure_super_admin_conf() {
  local ssh_target="$1"   # e.g. root@kcontrol01 or asiwko@kcontrol02
  local local_ip="$2"
  local use_sudo="$3"     # "sudo" or ""

  ssh -o ConnectTimeout=5 "$ssh_target" bash -s <<EOF
set -euo pipefail
if [ -f /etc/kubernetes/super-admin.conf ]; then
  echo "super-admin.conf already present"
  exit 0
fi
if [ -d /etc/kubernetes/super-admin.conf ]; then
  echo "clearing stray empty directory left by an earlier hostPath mount attempt"
  ${use_sudo} rmdir /etc/kubernetes/super-admin.conf
fi
echo "generating super-admin.conf (server: https://${local_ip}:6443, not the VIP)"
${use_sudo} kubeadm init phase kubeconfig super-admin --apiserver-advertise-address ${local_ip} --apiserver-bind-port 6443
EOF
}

write_manifest() {
  local ssh_target="$1"   # e.g. root@kcontrol01 or asiwko@kcontrol02
  local iface="$2"
  local use_sudo="$3"     # "sudo" or ""

  local tee_cmd="tee"
  if [ -n "$use_sudo" ]; then
    tee_cmd="sudo tee"
  fi

  ssh -o ConnectTimeout=5 "$ssh_target" "$tee_cmd /etc/kubernetes/manifests/kube-vip.yaml > /dev/null" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: kube-vip
  namespace: kube-system
spec:
  containers:
  - args:
    - manager
    env:
    - name: vip_arp
      value: "true"
    - name: port
      value: "6443"
    - name: vip_nodename
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
    - name: vip_interface
      value: ${iface}
    - name: vip_subnet
      value: "32"
    - name: dns_mode
      value: first
    - name: dhcp_mode
      value: ipv4
    - name: cp_enable
      value: "true"
    - name: cp_namespace
      value: kube-system
    - name: vip_leaderelection
      value: "true"
    - name: vip_leasename
      value: plndr-cp-lock
    - name: vip_leaseduration
      value: "15"
    - name: vip_renewdeadline
      value: "10"
    - name: vip_retryperiod
      value: "2"
    - name: address
      value: 192.168.50.155
    - name: prometheus_server
      value: :2112
    image: ghcr.io/kube-vip/kube-vip:v1.2.2
    imagePullPolicy: IfNotPresent
    name: kube-vip
    resources: {}
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
        drop:
        - ALL
    volumeMounts:
    - mountPath: /etc/kubernetes/admin.conf
      name: kubeconfig
  hostAliases:
  - hostnames:
    - kubernetes
    ip: 127.0.0.1
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/super-admin.conf
    name: kubeconfig
status: {}
EOF
}

echo "=== kcontrol01 (enp0s3, 192.168.50.160) ==="
ensure_super_admin_conf root@kcontrol01 192.168.50.160 ""
write_manifest root@kcontrol01 enp0s3 ""

echo "=== kcontrol02 (eth0, 192.168.50.156) ==="
ensure_super_admin_conf asiwko@kcontrol02 192.168.50.156 sudo
write_manifest asiwko@kcontrol02 eth0 sudo

echo "=== kcontrol03 (eth0, 192.168.50.157) ==="
ensure_super_admin_conf asiwko@kcontrol03 192.168.50.157 sudo
write_manifest asiwko@kcontrol03 eth0 sudo

echo
echo "Done. Verify with:"
echo "  kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip -o wide"
echo "  kubectl get pods -n kube-system | grep kube-vip"
echo "  kubectl get lease -n kube-system plndr-cp-lock -o jsonpath='{.spec.holderIdentity}'"
