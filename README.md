# SharkBait-setup

SharkBait-setup performs setup of a device to run Android as a container in Gentoo.  It's made up of the following two parts:

  * `decrypt.sh` disables force encryption that's present on the device, which prevents `preinit` from finding the Gentoo root and mounting it.
  * `deploy.sh` will be installed on the system as `sharkbait-deploy` and will set up the LXC root and mounts.

Ports to other devices are strongly welcomed!  Read the SharkBait-setup section in the [Porter's Guide](https://jsteward.moe/sharkbait-porters-guide.html) for more information.
