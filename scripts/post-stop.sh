#!/bin/bash

# do not reboot / restart when debugging
if [ -f /run/.android-debug ]; then
	echo "Debug mode, won't power off."
	exit 0
fi

# leave mark to prevent container restart
touch /run/.android-shutdown

if [ -f /run/.android-reboot ]; then
	echo "Rebooting..."
	reboot
else
	echo "Powering off..."
	poweroff
fi
