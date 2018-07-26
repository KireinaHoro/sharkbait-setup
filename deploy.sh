#!/bin/bash

CONTAINER_NAME=android
LXC_ROOT=/var/lib/lxc/$CONTAINER_NAME
ROOTFS=$LXC_ROOT/rootfs
DEVICE="$@"
FILES=(
pre-start.sh
post-stop.sh
config
)

tools=(
abootimg
blkid
cpio
gunzip
patch
)

detect_tools() {
    for a in ${tools[@]}; do
        which $a >/dev/null 2>&1 || die "Required tool $a not found in PATH"
    done
}
check_perm() {
    [ "$(whoami)" = "root" ] || die "This script must be ran as root"
}
check_device_support() {
    [ -z "$DEVICE" ] && die "usage: $0 <device>"
    [ -d "$dir/devices/$DEVICE" ] || die "Device $DEVICE is currently not supported"
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
tmpdir=/tmp/deploy-android-lxc_$(uuidgen)
dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
check_device_support
patches="$dir"/devices/$DEVICE/patches
mkdir -p $tmpdir || die "Failed to create temp dir $tmpdir"

mkdir -p $ROOTFS || die "Failed to create Android LXC root $ROOTFS"
info "Created $ROOTFS"
for a in ${FILES[@]}; do
    cp $a $LXC_ROOT || die "failed to copy $a to $LXC_ROOT"
done
info "Copied LXC files to $LXC_ROOT"

bootblk=/dev/block/bootdevice/by-name/boot
bootimg=$tmpdir/boot.img
ramdisk=$tmpdir/initrd.img
if [ ! -b $bootblk ]; then
    warn "/dev not in Android's structure, trying to detect via blkid"
    # need sudo to read raw block devices
    bootblk=$(blkid | sed -n -E -e 's|^(/dev/.*): PARTLABEL="boot".*$|\1|p')
    [ -b "$bootblk" ] || die "Failed to detect boot block location"
fi
dd if=$bootblk of=$bootimg || die "Failed to read current boot.img from $bootblk to $bootimg"
info "Read boot.img"

cd $tmpdir
abootimg -x $bootimg || die "Failed to unpack boot.img"
rm -rf "$ROOTFS"/* || die "Failed to empty current $ROOTFS"
cat $ramdisk | gunzip | cpio -vidD "$ROOTFS" || die "Failed to unpack initrd into $ROOTFS"
info "Unpacked initrd into $ROOTFS"

cd $ROOTFS
patch -p0 < <(cat "$patches/$DEVICE"/*) || die "Failed to apply patch to $ROOTFS"
info "Applied patches to $ROOTFS"

## TODO: fstab: per-device setup

lxc-info -n $CONTAINER_NAME || die "Failed to get information for container $CONTAINER_NAME"

info "All done! Try \`lxc-start android\`."

clean && exit 0
