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
awk
blkid
cpio
gunzip
patch
readlink
)

umask 022

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
    [ ! -z "$tmpdir" ] && rm -rf $tmpdir >/dev/null 2>&1 || true
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

setup_mark=/var/.sharkbait-setup-done
[ -f $setup_mark ] && die "System setup already done"
check_perm
detect_tools
tmpdir=/tmp/deploy-android-lxc_$(uuidgen)
dir="$( dirname $( readlink -f "${BASH_SOURCE[0]}" ) )"
FILES=( "${FILES[@]/#/"${dir}/"}" )
check_device_support
devdir="$dir"/devices/$DEVICE
patches="$devdir"/patches
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
patch -p0 < <(cat "$patches"/*) || die "Failed to apply patch to $ROOTFS"
info "Applied patches to $ROOTFS"

mv $ROOTFS/sbin/charger{,.real} || die "Failed to install charger wrapper"
cp "$dir"/scripts/charger $ROOTFS/sbin/charger || die "Failed to install charger wrapper"
chmod 750 $ROOTFS/sbin/charger || die "Failed to set permissions for charger wrapper"
info "Installed charger wrapper"

cat "$devdir"/fstab.android > /etc/fstab || die "Failed to write Android fstab"
info "Wrote Android fstab to system fstab"
for a in $(awk '$0!~"^$"&&$0!~"^#.*$"{print $2}' "$devdir"/fstab.android); do
    if [ ! -d "$a" ]; then
        if [ -L "$a" ]; then
            rm -f "$a" || die "Failed to remove stale symlink $a"
        fi
        mkdir -p "$a" || die "Failed to create mountpoint $a"
    fi
done
info "Created mountpoints for Android"
while read -r cmdline; do
    ln -s $cmdline || die "Failed to create symlinks of block devices"
done <<< $(awk '$1~"^/dev/.*$"{{$2=$1}{sub(/dev/,"dev/block")}{print $1" "$2}}' "$devdir"/fstab.android)
info "Created symlinks for block devices to mount"

disable_services_default=(
keymaps
termencoding
)
for a in "${disable_services_default[@]}"; do
    sudo rc-update del $a default || die "Failed to disable unnecessary service $a"
done
disable_services_sysinit=(
udev
udev-trigger
)
for a in "${disable_services_sysinit[@]}"; do
    sudo rc-update del $a sysinit || die "Failed to disable unnecessary service $a"
done
info "Disabled unnecessary services."
ln -sf /etc/init.d/lxc{,.android} || die "Failed to create Android container service"
rc-update add lxc.android default || die "Failed to enable Android container service"
info "Enabled Android container service"

sed -i -e 's/\(^[^#].*agetty.*$\)/#\1/' /etc/inittab || die "Failed to disable non-existent ttys in /etc/inittab"
info "Disabled non-existent ttys in /etc/inittab"
if [ -f "$devdir"/serial-consoles ]; then
    cat "$devdir"/serial-consoles >> /etc/inittab || die "Failed to enable serial consoles"
    info "Enabled serial consoles"
else
    info "This device does not have serial consoles available"
fi

ssh_root=/var/lib/android/data/ssh
mount -a || die "Failed to mount some of the filesystems"
mkdir -p $ssh_root || die "Failed to create $ssh_root"
info "Will now create ssh keys for Android to dial back to Gentoo..."
ssh-keygen -t ed25519 -f $ssh_root/id_ed25519 -C "Android dialhome" \
    || die "Failed to create ssh keys"
mkdir -p /root/.ssh || die "Failed to create root ssh directory"
cat $ssh_root/id_ed25519.pub >> /root/.ssh/authorized_keys || die "Failed to add public key to root auth list"
cp "$dir"/scripts/dialhome $ssh_root || die "Failed to copy dialhome script to $ssh_home"
chmod 700 $ssh_root/dialhome || die "Failed to set permissions for dialhome script"
chown -R 2000:2000 $ssh_root || die "Failed to set owners for $ssh_root"
rc-update add sshd default || die "Failed to enable sshd service"
info "Use /data/ssh/dialhome in Android to ssh back to Gentoo."
warn "sshd with default configuration enabled.  You may want to change"
warn "sshd configuration for security considerations."

lxc-info -n $CONTAINER_NAME || die "Failed to get information for container $CONTAINER_NAME"

touch $setup_mark || die "Failed to place setup finish mark in /var"
info "All done! Proceed with the rest of the User Guide."

clean && exit 0
