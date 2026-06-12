#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.2}"
UBUNTU_ISO_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}/ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
ORIGINAL_ISO="ubuntu-original.iso"
WORK_DIR="iso-work"
OUTPUT_ISO="${OUTPUT_ISO:-ubuntu-autoinstall.iso}"
USER_DATA_FILE="${USER_DATA_FILE:-user-data}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# 1. Download ISO
if [[ ! -f "$ORIGINAL_ISO" ]]; then
  log "Downloading Ubuntu ${UBUNTU_VERSION} ISO..."
  wget -q --show-progress -O "$ORIGINAL_ISO" "$UBUNTU_ISO_URL" \
    || die "Failed to download ISO"
fi

# 2. Extract ISO
log "Extracting ISO..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
MOUNT_DIR=$(mktemp -d)
mount -o loop,ro "$ORIGINAL_ISO" "$MOUNT_DIR"
rsync -a "$MOUNT_DIR/" "$WORK_DIR/"
umount "$MOUNT_DIR"
rm -rf "$MOUNT_DIR"
chmod -R u+w "$WORK_DIR"

# 3. Inject autoinstall config
log "Injecting autoinstall config..."
mkdir -p "$WORK_DIR/autoinstall"

if [[ -f "$USER_DATA_FILE" ]]; then
  cp "$USER_DATA_FILE" "$WORK_DIR/autoinstall/user-data"
elif [[ -f "user-data.example" ]]; then
  log "WARNING: using user-data.example"
  cp "user-data.example" "$WORK_DIR/autoinstall/user-data"
else
  die "No user-data file found!"
fi
touch "$WORK_DIR/autoinstall/meta-data"

# 4. Patch GRUB
log "Patching GRUB..."
GRUB_CFG="$WORK_DIR/boot/grub/grub.cfg"
if [[ -f "$GRUB_CFG" ]]; then
  cat > /tmp/grub-patch.cfg << 'EOF'
set timeout=5
set default=0

menuentry "Ubuntu Autoinstall" {
    set gfxpayload=keep
    linux   /casper/vmlinuz quiet autoinstall ds=nocloud\;s=/cdrom/autoinstall/ ---
    initrd  /casper/initrd
}

EOF
  grep -Ev '^set (default|timeout)=' "$GRUB_CFG" >> /tmp/grub-patch.cfg || true
  cp /tmp/grub-patch.cfg "$GRUB_CFG"
fi

# 5. Rebuild ISO
log "Building $OUTPUT_ISO..."
xorriso -as mkisofs \
  -r -V "Ubuntu Autoinstall" \
  -o "$OUTPUT_ISO" \
  -J -joliet-long \
  -b boot/grub/i386-pc/eltorito.img \
  -c boot.catalog \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  --grub2-boot-info \
  --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
  -eltorito-alt-boot \
  -e EFI/boot/bootx64.efi \
  -no-emul-boot \
  -append_partition 2 0xef "$WORK_DIR/EFI/boot/bootx64.efi" \
  "$WORK_DIR"

log "✅ Done: $OUTPUT_ISO"
