#!/usr/bin/env bash
# Clone le template cloud-init (VMID 9000) pour créer les VM du lab.
# À lancer sur un nœud Proxmox. Adapter les variables ci-dessous.
set -euo pipefail

TEMPLATE_ID=9000
STORAGE=local-lvm
BRIDGE=vmbr0
GW=10.10.10.1
DNS=10.10.10.1
SSH_KEY=~/.ssh/id_ed25519.pub

#   nom     vmid  ip            vcpu ram(Mo) disque(Go)
VMS=$(cat <<'LIST'
cm01     110  10.10.10.10   2    4096   30
idx01    111  10.10.10.11   2    4096   60
idx02    112  10.10.10.12   2    4096   60
idx03    113  10.10.10.13   2    4096   60
dep01    120  10.10.10.20   1    2048   20
sh01     121  10.10.10.21   2    4096   30
sh02     122  10.10.10.22   2    4096   30
sh03     123  10.10.10.23   2    4096   30
ing01    130  10.10.10.30   4    8192   40
ops01    140  10.10.10.40   4    12288  60
lnx01    150  10.10.10.50   1    1024   10
LIST
)

while read -r name vmid ip cpu ram disk; do
  [[ -z "$name" ]] && continue
  if qm status "$vmid" &>/dev/null; then echo "VM $vmid ($name) existe déjà"; continue; fi
  echo ">> $name ($vmid) $ip"
  qm clone "$TEMPLATE_ID" "$vmid" --name "$name" --full true --storage "$STORAGE"
  qm set "$vmid" --cores "$cpu" --memory "$ram" --net0 "virtio,bridge=$BRIDGE" \
    --ipconfig0 "ip=${ip}/24,gw=${GW}" --nameserver "$DNS" --searchdomain lab.local \
    --sshkeys "$SSH_KEY" --ciuser ansible --agent enabled=1
  qm resize "$vmid" scsi0 "${disk}G"
  qm start "$vmid"
done <<< "$VMS"
