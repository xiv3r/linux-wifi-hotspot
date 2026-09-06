# 5GHz hotspots on Intel adapters (iwlwifi)

Most "I cannot start a 5GHz hotspot" reports on Intel cards come down to two
*separate* restrictions. They have different causes and different answers, so
work out which one you are hitting before changing anything.

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Your adapter can not transmit to channel 36, frequency band 5GHz` | every 5GHz channel is flagged `no IR` | [disable LAR](#disabling-lar) |
| `Failed to set beacon parameters` / `Interface initialization failed` | the AP must share the channel your WiFi client is on | nothing to do, `create_ap` now handles it |

## Which one am I hitting?

```
iw reg get | head -5
iw phy "$(iw dev | awk '/^phy#/{gsub("#","");print $1;exit}')" info | grep 'MHz \[' | grep '5[0-9]\{3\}'
```

If the output looks like this, you have the regulatory problem:

```
phy#0 (self-managed)
country 00: DFS-UNSET
...
	* 5180.0 MHz [36] (22.0 dBm) (no IR)
	* 5745.0 MHz [149] (22.0 dBm) (no IR)
```

Two things matter: **`(self-managed)`** and **`(no IR)`** on every 5GHz channel.

## Why it happens

Intel adapters use LAR (Location Aware Regulatory). The regulatory domain lives
in the adapter firmware rather than in the kernel's `regulatory.db`, and the
wiphy is marked *self-managed*. When the firmware has not learned a country it
sits on the world domain `country 00`, where every 5GHz channel carries `no IR`.

**IR** is "Initiate Radiation". `no IR` means you may not start transmitting on
that channel on your own initiative - you may only answer something already
there. That is exactly the difference between a client and an access point:

* joining a 5GHz network works, because a client listens first and only then
  replies;
* hosting does not, because an access point beacons unprompted.

So on an affected card you can *connect* over 5GHz but never *host* on it.

Things that do **not** help:

* `iw reg set XX` - a self-managed wiphy ignores it. The country comes from
  firmware.
* Being associated to a router that broadcasts a Country IE - the firmware
  often still stays on `country 00`.
* The kernel's `IR-CONCURRENT` relaxation, which allows beaconing on a `no IR`
  channel while already associated on it. It is unusable twice over:
  `CONFIG_CFG80211_REG_RELAX_NO_IR` depends on `CFG80211_CERTIFICATION_ONUS`,
  which distributions do not enable, and even when built in,
  `cfg80211_ir_permissive_chan()` only allows `P2P_GO`, `STATION` and
  `P2P_CLIENT`. A plain AP interface is excluded.

## Disabling LAR

`iwlwifi` used to ship a `lar_disable=1` module parameter for exactly this, and
it was removed. The scripts in [`util/iwlwifi-lar-disable/`](../../util/iwlwifi-lar-disable)
put it back: a two file patch to `iwlmvm` that stops the driver claiming a
self-managed regulatory domain, so the kernel database applies and `iw reg set`
starts working.

> **This moves regulatory responsibility to you.** Set the country you are
> actually in and only operate on channels your regulator permits. Disabling
> LAR does not grant you spectrum, it just stops the firmware being
> conservative.

### 1. Build

```
cd util/iwlwifi-lar-disable
./build.sh
```

It needs your kernel headers and kernel source. On Debian/Ubuntu it installs
`linux-source-*` itself; elsewhere install your distribution's kernel source
package, or point it at an unpacked tree:

```
KERNEL_SRC=/path/to/linux ./build.sh
```

### 2. Enroll a signing key (Secure Boot only)

If Secure Boot is on, `build.sh` signs the module and prints the enrollment
command. Unsigned modules are refused, so this step is not optional:

```
sudo mokutil --import /var/lib/linux-wifi-hotspot/lar/MOK.der
```

Pick a one-time password and reboot. A blue **MOK Manager** screen appears
before the OS loads:

1. press a key at the *"Press any key to perform MOK management"* countdown -
   letting it expire silently discards the request, which is the single most
   common reason this step fails;
2. `Enroll MOK` -> `Continue` -> `Yes`;
3. type the password from above (US keyboard layout);
4. `Reboot`.

### 3. Install

```
sudo COUNTRY=LK ./install.sh     # use your own two letter country code
sudo reboot
```

`install.sh` refuses to run while the key is unenrolled, so there is never a
boot with an unloadable WiFi module.

### 4. Verify

```
iw reg get | head -3
```

The per-phy `(self-managed)` block should be gone and the country should be
yours. Then:

```
iw phy "$(iw dev | awk '/^phy#/{gsub("#","");print $1;exit}')" info | grep 'MHz \[' | grep '5[0-9]\{3\}'
```

The `(no IR)` suffix should have disappeared from the non-DFS channels. Connect
to a 5GHz network and start the hotspot as usual - `create_ap` puts the AP on
the channel your client is already using.

### Reverting

```
sudo util/iwlwifi-lar-disable/uninstall.sh
sudo reboot
```

## After a kernel upgrade

The module is installed into `/lib/modules/<version>/updates/`, so a new kernel
loads the distribution module again and 5GHz hotspots stop working. Nothing
breaks, but you have to rebuild:

```
cd util/iwlwifi-lar-disable && ./build.sh && sudo COUNTRY=LK ./install.sh
```

The signing key stays enrolled across kernel upgrades, so only the build and
install steps repeat.

## The other restriction: one channel at a time

Independently of any of the above, since Linux 6.11 `iwlwifi` only advertises AP
mode in a single-channel interface combination (kernel commit `5c38bedac16a`):

```
* #{ managed } <= 1, #{ P2P-client, P2P-GO } <= 1, ...  #channels <= 2   <- no AP
* #{ managed } <= 1, #{ AP, P2P-client, P2P-GO } <= 1,  #channels <= 1   <- the AP one
```

The access point therefore has to sit on **the same channel your WiFi client is
connected to**. Asking for anything else gets you hostapd's
`Failed to set beacon parameters`.

`create_ap` reads this out of the driver and follows the client's channel
automatically, so in practice:

* connected to a 2.4GHz network -> you get a 2.4GHz hotspot;
* connected to a 5GHz network -> you get a 5GHz hotspot on that channel;
* asking for a band the client is not on is refused with an explanation.

This is a hardware and driver limitation. Disabling LAR does not change it, and
there is no `create_ap` option that works around it. To host on a specific
channel, connect the client to a network on that channel, or share a different
uplink such as ethernet.

## Channel width

Some regulatory domains cap 5GHz channels at 20MHz in the kernel database even
where the firmware previously allowed 80MHz, so disabling LAR can narrow both
the hotspot *and* your normal client connection. Check with:

```
iw reg get
```

A rule like `(5735 - 5835 @ 20)` means 20MHz maximum; `@ 80` means 80MHz is
available. `create_ap --ieee80211ac --vht-chwidth 80` asks for 80MHz and
automatically falls back to whatever the regulatory domain allows, reporting
what it settled on. If your country's entry looks wrong, the fix belongs
upstream in [wireless-regdb](https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git).

## Non-Intel adapters

This guide is specific to `iwlwifi`. Realtek users should see
[realtek.md](realtek.md). Adapters from other vendors that report a
self-managed regulatory domain have the same underlying problem but need a
driver-specific change; the diagnosis section above still applies.
