#!/bin/bash

DEVICE="$@"

check_perm() {
    [ "$(whoami)" = "root" ] || die "This script must be ran as root"
}
check_device_support() {
    [ -z "$DEVICE" ] && die "usage: $0 <device>"
    [ -d "$dir/devices/$DEVICE" ] || die "Device $DEVICE is currently not supported"
}
info() {
    echo "[INFO] $@" 
}
warn() {
    echo "[WARN] $@" >&2
}
die() {
    echo "[ERR ] $@" >&2
    exit 1
}

check_perm
dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
check_device_support
devdir="$dir"/devices/$DEVICE

info "Decrypting for device $DEVICE..."
exec $devdir/disable_encryption.sh
