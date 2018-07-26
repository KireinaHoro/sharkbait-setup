#!/bin/bash

DEVICE="$@"

tools=(
readlink
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
detect_tools
dir="$( dirname $( readlink -f "${BASH_SOURCE[0]}" ) )"
check_device_support
devdir="$dir"/devices/$DEVICE

info "Decrypting for device $DEVICE..."
exec $devdir/disable_encryption.sh
