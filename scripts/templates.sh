#!/bin/bash
# Purpose: Build Proxmox VM templates from cloud images, safely and repeatably
# 11/8/2025 ; Theo LINDER

# -------------------- Configuration --------------------
declare -A LINKS=(
    # Key -> cloud image URL
    ["debian-13"]="https://cdimage.debian.org/cdimage/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
    ["ubuntu-noble"]="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    ["alpine-3.22"]="https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/cloud/generic_alpine-3.22.2-x86_64-uefi-cloudinit-r0.qcow2"
)

ALLOWED=("debian-13" "ubuntu-noble" "alpine-3.22")

PROXMOX_START_ID=9000               # lower bound for VMIDs
IMG_DEST="/tmp/"                    # download location
PROXMOX_STORAGE="zfs-vms"           # proxmox storage ID to hold disks and cloud-init
MEMORY=1024                         # MiB
NET_BRIDGE="vmbr0"                  # network bridge

#------------- Helpers -------------

die() { echo "Error: $*"; exit 1; }

cmd_ok() { command -v "$1" > /dev/null 2>&1; }

# Verify that the storage ID exists in proxmox
require_storage() {
    local sid="$1"
    pvesm status | awk 'NR>1{print $1}' | grep -qx "$sid"
}

vmid_by_name() {
  # Returns VMID if a VM/CT with given name exists, else prints nothing
  local name="$1" id=""
  id="$(qm list 2>/dev/null | awk -v n="$name" 'NR>1 && $2==n {print $1; exit}')" || true
  [[ -n "$id" ]] && { echo "$id"; return 0; }
  id="$(pct list 2>/dev/null | awk -v n="$name" 'NR>1 && $2==n {print $1; exit}')" || true
  [[ -n "$id" ]] && echo "$id" || true
}

# First free VMID >= PROXMOX_START_ID
pick_vmid() {
  local start="$1" id

  id="$(pvesh get /cluster/nextid 2>/dev/null || true)"

  if [[ -z "${id:-}" || "$id" -lt "$start" ]]; then
    id="$start"
  fi

  while qm status "$id" &>/dev/null || pct status "$id" &>/dev/null; do
    id=$(( id + 1 ))
  done

  echo "$id"
}

validate_args() {
  # Ensures every argument is allowed and has a URL defined
  local arg ok
  for arg in "$@"; do
    ok=false
    for a in "${ALLOWED[@]}"; do
      if [[ "$arg" == "$a" ]]; then ok=true; break; fi
    done
    [[ "$ok" == true ]] || die "Bad parameter: $arg. Allowed: ${ALLOWED[*]}"
    [[ -n "${LINKS[$arg]+_}" ]] || die "No URL defined for key: $arg"
  done
}

# -------------------- Preconditions --------------------

# Require at least one template key
[[ "$#" -ge 1 ]] || die "Usage: $0 template-1 [template-2 ...]"

# Tools. Install if missing
if ! ( cmd_ok wget && cmd_ok virt-customize ); then
    apt-update -y
    apt-get install -y wget libguestfs-tools || die "Failed to install dependencies"
fi

# Verify storage
require_storage "$PROXMOX_STORAGE" || die "Storage '$PROXMOX_STORAGE' not found in 'pvesm status'"

# Verify args
validate_args "$@"

# Create download directory if missing
mkdir -p "$IMG_DEST"

# -------------------- Main loop --------------------
for arg in "$@"; do
  name="${arg}-template"

  # Rule: if a template with the same name already exists, do nothing
  if existing="$(vmid_by_name "$name")" && [[ -n "${existing:-}" ]]; then
    echo "Skip: '$name' already exists (VMID $existing). No changes."
    continue
  fi

  url="${LINKS[$arg]}"
  filename="${url##*/}"
  path="${IMG_DEST%/}/${filename}"

  echo "Downloading: $url -> $path"
  wget -O "$path" "$url"

  echo "Injecting qemu-guest-agent into: $path"
  virt-customize -a "$path" --install qemu-guest-agent

  # First free VMID >= PROXMOX_START_ID
  vmid="$(pick_vmid "$PROXMOX_START_ID")"
  [[ -n "$vmid" ]] || { echo "no VMID computed" >&2; exit 1; }

  echo "Creating VMID $vmid name '$name'"
  qm create "$vmid" \
    --name "$name" \
    --memory "$MEMORY" \
    --net0 "virtio,bridge=${NET_BRIDGE}"

  echo "Importing disk to storage '$PROXMOX_STORAGE'"
  qm importdisk "$vmid" "$path" "$PROXMOX_STORAGE"

  # On ZFS, import names the disk like 'zfs-vms:vm-<vmid>-disk-0'
  echo "Attaching disk and configuring boot and cloud-init"
  qm set "$vmid" --scsihw virtio-scsi-pci --scsi0 "${PROXMOX_STORAGE}:vm-${vmid}-disk-0"
  qm set "$vmid" --ide2 "${PROXMOX_STORAGE}:cloudinit"
  qm set "$vmid" --boot c --bootdisk scsi0
  qm set "$vmid" --serial0 socket --vga serial0
  qm set "$vmid" --ipconfig0 ip=dhcp

  # Resize disk to 50G when possible; ignore if image layout prevents grow
  qm resize "$vmid" scsi0 50G || echo "Resize skipped."

  echo "Converting to template"
  qm template "$vmid"
  qm set "$vmid" --tags "template,cloud,$arg"

  # Clean local image copy
  rm -f "$path"

  echo "OK: $name -> VMID $vmid"
done
