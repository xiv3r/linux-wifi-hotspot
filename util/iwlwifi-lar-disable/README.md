# iwlwifi `lar_disable`

Restores the `lar_disable` module parameter that `iwlwifi` used to ship, so an
Intel adapter stops claiming a self-managed regulatory domain and the kernel
regulatory database applies instead. Without this every 5GHz channel stays
flagged `no IR` and cannot host an access point.

**Read [docs/howto/intel-5ghz-lar.md](../../docs/howto/intel-5ghz-lar.md) first** -
it explains how to tell whether this is actually your problem, and covers the
Secure Boot key enrollment that the install step depends on.

```
./build.sh                    # patch, build and sign against the running kernel
sudo COUNTRY=XX ./install.sh  # install and enable, XX = your country code
sudo ./uninstall.sh           # revert
```

| File | Purpose |
| --- | --- |
| `lar_disable.patch` | the driver change, two files under `drivers/net/wireless/intel/iwlwifi/mvm` |
| `build.sh` | fetches kernel source, applies the patch, builds and signs `iwlmvm.ko` |
| `install.sh` | installs into `/lib/modules/<ver>/updates/` and writes the modprobe options |
| `uninstall.sh` | removes both and restores the distribution module |

Build artefacts and the generated signing key live in
`/var/lib/linux-wifi-hotspot/lar`. The key is never stored in this repository.

This has to be repeated after a kernel upgrade; the enrolled signing key
persists, so only `build.sh` and `install.sh` need re-running.
