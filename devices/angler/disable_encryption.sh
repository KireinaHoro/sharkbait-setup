#!/bin/bash

DEVICE=angler

tools=(
abootimg
adb
cpio
fastboot
gunzip
gzip
)

detect_tools() {
    for a in ${tools[@]}; do
        which $a >/dev/null 2>&1 || die "Required tool $a not found in PATH"
    done
}
check_perm() {
    [ "$(whoami)" = "root" ] || die "This script must be ran as root"
}
show_warning() {
    delay=10
    warn "This script is for device $DEVICE.  Using this script"
    warn "on other devices may fail or cause damage to your device."
    warn "This script will wipe all user data on your device."
    warn "Make sure you backup important data on the device before"
    warn "continuing."
    warn "Waiting $delay seconds before continuing..."
    sleep $delay
}
clean() {
    rm -rf $tmpdir >/dev/null 2>&1 || true
}
info() {
    echo "[INFO] $@" 
}
warn() {
    echo "[WARN] $@" >&2
}
die() {
    echo "[ERR ] $@" >&2
    clean && exit 1
}

check_perm
detect_tools
show_warning
tmpdir=/tmp/disable-encryption_$(uuidgen)
mkdir -p $tmpdir || die "Failed to create temp dir $tmpdir"

bootblk=/dev/block/bootdevice/by-name/boot
bootimg=$tmpdir/boot.img
newbootimg=$tmpdir/new.img

adb devices | grep "device$" || \
    die "Device not found or unauthorized.  Fix adb access and try again."
info "Found device"
adb root || die "Failed to restart adbd as root"
sleep 2

cd $tmpdir
adb pull $bootblk $bootimg || die "Failed to pull boot.img from device"
info "Pulled boot.img from device"
abootimg -x $bootimg || die "Failed to unpack boot.img"
mkdir rootfs
cat initrd.img | gunzip | cpio -vidD rootfs || die "Failed to unpack initrd"
info "Unpacked initramfs"

# ============================================================
# Device-specific logic -- change forcefdeorfbe to encryptable
# ============================================================
sed -i -e 's/forcefdeorfbe/encryptable/g' rootfs/fstab.$DEVICE || die "Failed to modify fstab.$DEVICE to disable encryption"
info "Modified fstab.$DEVICE to disable encryption"
# ============================================================
# End of device-specific logic
# ============================================================

pushd rootfs >/dev/null
find . | cpio --create --format='newc' | gzip > ../initrd.img || die "Failed to create new initrd"
popd >/dev/null
sed -i bootimg.cfg \
    -e '/bootsize/d' \
    -e 's/enforcing/permissive/g' \
    -e 's/\(cmdline.=.\)/\1androidboot.selinux=permissive /g' \
    || die "Failed to modify bootimg.cfg to remove size limit"
abootimg --create $newbootimg -f bootimg.cfg -k zImage -r initrd.img || die "Failed to create new boot.img"
info "Created new boot.img"

adb reboot bootloader || die "Failed to reboot phone"

info "Waiting 10 seconds for device to show up in fastboot mode..."
sleep 10
fastboot flash boot $newbootimg || die "Failed to flash new boot.img"
info "Flashed new boot.img"
fastboot format userdata || die "Failed to format userdata"
info "Erased userdata"
fastboot format cache || die "Failed to format cache"
info "Erased cache"
fastboot reboot || die "Failed to reboot phone"
info "Rebooting phone..."

info "All done! Check mount information to see if encryption has been disabled."

clean && exit 0
