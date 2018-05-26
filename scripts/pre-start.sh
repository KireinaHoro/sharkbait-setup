#!/bin/sh

mkdir -p /run
if [ -f /run/.android-shutdown ]; then
	# we're shutting down; don't respawn
	echo "Shutting down, won't restart."
	exit 1
fi

# handle cgroup
mkdir /sys/fs/cgroup/cpu/lxc
echo 950000 > /sys/fs/cgroup/cpu/lxc/cpu.rt_runtime_us
