#!/usr/bin/env bash
# Создание cloud-init шаблона Debian 12 (ID 9000) на ноде Proxmox.
# Запуск: на pve-01 от root. Идемпотентно: если шаблон есть — выход.
set -euo pipefail

TEMPLATE_ID=9000
TEMPLATE_NAME="debian-12-cloud"
STORAGE="local-lvm"
IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
IMG_FILE="/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2"

if qm status "$TEMPLATE_ID" &>/dev/null; then
  echo "Шаблон $TEMPLATE_ID уже существует — выход."
  exit 0
fi

mkdir -p "$(dirname "$IMG_FILE")"
[ -f "$IMG_FILE" ] || wget -q "$IMG_URL" -O "$IMG_FILE"

qm create "$TEMPLATE_ID" --name "$TEMPLATE_NAME" --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk "$TEMPLATE_ID" "$IMG_FILE" "$STORAGE"
qm set "$TEMPLATE_ID" --scsihw virtio-scsi-single --scsi0 "$STORAGE:vm-$TEMPLATE_ID-disk-0,discard=on,iothread=1"
qm set "$TEMPLATE_ID" --ide2 "$STORAGE:cloudinit" --boot c --bootdisk scsi0
qm set "$TEMPLATE_ID" --serial0 socket --vga serial0
qm set "$TEMPLATE_ID" --agent enabled=1
qm set "$TEMPLATE_ID" --ciuser sysadmin
# ssh-ключ админа (заменить на свой перед запуском):
# qm set "$TEMPLATE_ID" --sshkey /root/.ssh/id_ed25519.pub
qm template "$TEMPLATE_ID"

echo "Готово: шаблон $TEMPLATE_ID ($TEMPLATE_NAME). Укажите его в terraform (vm_template_id = 9000)."
