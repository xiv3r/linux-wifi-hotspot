#!/bin/bash
# Undo install.sh and go back to the distribution iwlmvm.
set -euo pipefail
KVER=$(uname -r)
SUDO=
[[ $EUID -ne 0 ]] && SUDO=sudo

$SUDO rm -f "/lib/modules/$KVER/updates/iwlmvm.ko"
$SUDO rm -f /etc/modprobe.d/iwlmvm-lar-disable.conf
$SUDO rm -f /etc/modprobe.d/cfg80211-regdom.conf
$SUDO depmod -a
echo "==> Reverted. Reboot to load the distribution module again."
echo "    Build artefacts and the signing key are kept in /var/lib/linux-wifi-hotspot/lar"
