#!/bin/bash
# Install the module built by build.sh and turn lar_disable on.
#
#   sudo ./install.sh              install, leave the regulatory country alone
#   sudo COUNTRY=LK ./install.sh   also pin the regulatory country
set -euo pipefail

KVER=$(uname -r)
STATE_DIR=/var/lib/linux-wifi-hotspot/lar
MODULE=$STATE_DIR/iwlmvm.ko

SUDO=
[[ $EUID -ne 0 ]] && SUDO=sudo

die() { echo "ERROR: $*" >&2; exit 1; }
say() { echo "==> $*"; }

# mokutil exits non-zero when it cannot read the kernel trusted keyring even
# though the answer on stdout is correct, so match the text and ignore status.
secure_boot_on() {
    local out; out=$(mokutil --sb-state 2>/dev/null || true)
    [[ "$out" == *"SecureBoot enabled"* ]]
}
mok_enrolled() {
    local out; out=$(mokutil --test-key "$1" 2>/dev/null || true)
    [[ "$out" == *"is already enrolled"* ]]
}


[[ -f "$MODULE" ]] || die "no module at $MODULE - run build.sh first"

# Refuse rather than leave an unloadable module in the boot path: under Secure
# Boot an unenrolled signature means no WiFi at all after the next reboot.
if secure_boot_on; then
    if ! mok_enrolled "$STATE_DIR/MOK.der"; then
        die "Secure Boot is on and $STATE_DIR/MOK.der is not enrolled.
       Run:  sudo mokutil --import $STATE_DIR/MOK.der
       then reboot and complete the MOK Manager screen."
    fi
fi

say "installing iwlmvm.ko into /lib/modules/$KVER/updates/"
$SUDO install -D -m644 "$MODULE" "/lib/modules/$KVER/updates/iwlmvm.ko"
$SUDO depmod -a

say "enabling lar_disable"
printf 'options iwlmvm lar_disable=1\n' |
    $SUDO tee /etc/modprobe.d/iwlmvm-lar-disable.conf >/dev/null

if [[ -n "${COUNTRY:-}" ]]; then
    say "pinning regulatory country to $COUNTRY"
    printf 'options cfg80211 ieee80211_regdom=%s\n' "$COUNTRY" |
        $SUDO tee /etc/modprobe.d/cfg80211-regdom.conf >/dev/null
else
    cat <<'EOF'

NOTE: no COUNTRY was given. Without a regulatory country the adapter falls back
      to the world domain ("country 00"), where every 5GHz channel is still
      flagged "no IR" and cannot host an AP. Either re-run with
      COUNTRY=<your two letter code>, or rely on your router's Country IE.
EOF
fi

cat <<EOF

Done. Reboot, then check:

    iw reg get | head -3

The per-phy "(self-managed)" block should be gone and the country should be
yours. Confirm the 5GHz channels lost their "no IR" flag with:

    iw phy \$(iw dev | awk '/^phy#/{gsub("#","");print \$1;exit}') info | grep '5[0-9]\{3\}\.0 MHz'

Revert at any time with:  sudo $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/uninstall.sh
EOF
