# Hailo-8 AI Accelerator Sysext for TrueNAS SCALE

A systemd-sysext package that adds [Hailo-8](https://hailo.ai/) AI accelerator support to TrueNAS SCALE. Primarily useful for running [Frigate NVR](https://frigate.video/) with hardware-accelerated AI object detection.

## What's Included

The `hailo.raw` sysext contains:

| Component | Description |
| --- | --- |
| `hailo_pci.ko` | PCIe kernel module (compiled for exact TrueNAS kernel) |
| `libhailort.so` | HailoRT runtime library |
| `hailortcli` | HailoRT command-line tool |
| `hailo-load.service` | Systemd service for automatic module loading |
| `51-hailo-udev.rules` | Udev rules for `/dev/hailo*` permissions |

> **Note:** Hailo-8 firmware (`hailo8_fw.bin`) is **not** included in the release.
> It is proprietary (Hailo's EULA prohibits redistribution) and is downloaded
> directly from Hailo's servers during installation.

## Quick Start

### Prerequisites

- TrueNAS SCALE 25.10.x (Goldeye) or compatible
- Hailo-8 PCIe AI accelerator installed and visible (`lspci | grep Hailo`)
- Root/sudo access
- Internet access (to download the release and firmware)

### Install

The simplest way — auto-detects your TrueNAS version, downloads the matching release, fetches firmware from Hailo, and sets up persistence:

```bash
curl -fsSL https://github.com/scyto/truenas-hailo/releases/latest/download/install.sh | sudo bash
```

With an explicit pool for persistence:

```bash
curl -fsSL https://github.com/scyto/truenas-hailo/releases/latest/download/install.sh -o install.sh
sudo bash install.sh --pool=fast
```

> **Version matching:** Each release is built for a specific TrueNAS kernel. The install script
> auto-detects your TrueNAS version and downloads the correct release. If no matching release
> exists for your version, the script will error with a list of available releases.

#### Installing a Specific Version

Release tags encode both versions: `v<truenas>-hailo<driver>` (e.g., `v25.10.2.1-hailo4.21.0`).

To install from a specific release:

```bash
# Download install.sh from a specific release tag
curl -fsSL https://github.com/scyto/truenas-hailo/releases/download/v25.10.2.1-hailo4.21.0/install.sh | sudo bash
```

Or download `hailo.raw` manually and install it:

```bash
# Download hailo.raw from a specific release
curl -fSL https://github.com/scyto/truenas-hailo/releases/download/v25.10.2.1-hailo4.21.0/hailo.raw -o /tmp/hailo.raw
sudo bash install.sh /tmp/hailo.raw
```

> **Warning:** Using a `hailo.raw` built for a different TrueNAS version will fail to load
> the kernel module. The module is compiled against exact kernel headers — a version mismatch
> means `insmod` will refuse to load it. Always use the release matching your TrueNAS version.

#### Install Options

| Option | Description |
| --- | --- |
| `--pool=NAME` | ZFS pool for persistent config (e.g., `fast`) |
| `--persist-path=PATH` | Exact path for persistent config directory |
| `--help` | Show usage help |

### What the Install Script Does

1. **Downloads `hailo.raw`** from the GitHub release matching your TrueNAS version (or uses a local file)
2. **Verifies the checksum** (SHA256)
3. **Downloads Hailo-8 firmware** directly from Hailo's S3 servers (not redistributed by this project)
4. **Injects firmware** into the sysext squashfs (unpacks, adds firmware, repacks)
5. **Installs the sysext** to `/usr/share/truenas/sysext-extensions/hailo.raw`
6. **Activates the sysext** via TrueNAS's symlink + refresh pattern
7. **Loads the kernel module** via `insmod`
8. **Sets up persistence** (see below)

### Verify

```bash
# Check device is detected
ls -la /dev/hailo*

# Check kernel module is loaded
lsmod | grep hailo

# Check PCI device has driver bound
lspci -v | grep -A2 Hailo

# Query firmware (hailortcli 4.21+ syntax)
sudo hailortcli fw-control identify
```

### Uninstall

```bash
curl -fsSL https://github.com/scyto/truenas-hailo/releases/latest/download/restore.sh | sudo bash
```

This removes the sysext, deregisters the init script, and cleans up persistent storage.

## Persistence

TrueNAS updates replace the rootfs, which wipes `/usr/` and any installed sysext. The install script sets up automatic recovery:

### Recovery Process

1. **Backup**: The sysext (with firmware already injected) is copied to a persistent ZFS pool
2. **PREINIT script**: Registered with TrueNAS middleware, runs on every boot before apps start
3. On boot, the script compares checksums — if the installed sysext differs from the backup (indicating a TrueNAS update) or is missing, it reinstalls from the backup
4. No network access is needed at boot — firmware is already inside the backed-up sysext

### Persistent Storage Layout

```text
/mnt/<pool>/.config/hailo/
├── hailo.raw                ← Sysext backup (includes firmware)
├── .hailo-driver-version    ← HailoRT version (informational)
└── hailo-preinit.sh         ← Boot script (registered as PREINIT)
```

### Pool Selection

The install script selects a pool in this order:

1. `--persist-path=PATH` — use this exact path (highest priority)
2. `--pool=NAME` — use `/mnt/<NAME>/.config/hailo`
3. **Auto-detect** — first ZFS pool that isn't `boot-pool`

The PREINIT script finds the config at boot by scanning `/mnt/*/.config/hailo/`, so it works even if the pool name changes.

## Using with Frigate

After installing the sysext, configure Frigate to use the Hailo-8:

### 1. Pass Through the Device

In TrueNAS Apps, edit your Frigate app and add the device mapping:

```text
/dev/hailo0:/dev/hailo0
```

### 2. Configure Frigate Detectors

In your Frigate `config.yaml`:

```yaml
detectors:
  hailo8l:
    type: hailo8l    # Use hailo8l for both Hailo-8 and Hailo-8L
    device: PCIe

model:
  width: 640
  height: 640
  input_tensor: nhwc
  input_pixel_format: rgb
  input_dtype: int
  model_type: yolo-generic
```

> **Note:** Frigate uses `hailo8l` as the detector type for **both** Hailo-8 and Hailo-8L devices.

For a larger model (Hailo-8 has more capacity than 8L), add a `path` to the model section:

```yaml
model:
  width: 640
  height: 640
  input_tensor: nhwc
  input_pixel_format: rgb
  input_dtype: int
  model_type: yolo-generic
  path: https://hailo-model-zoo.s3.eu-west-2.amazonaws.com/ModelZoo/Compiled/v2.17.0/hailo8/yolov8m.hef
```

You can keep `ffmpeg.hwaccel_args: preset-nvidia` if you have an NVIDIA GPU — video decoding (GPU) and AI detection (Hailo) are independent.

## How It Works

### Build Process

Unlike the [NVIDIA sysext](https://github.com/scyto/truenas-nvidia-blackwell) which requires the full TrueNAS `scale-build` pipeline (~5-6 hours), this project compiles the Hailo driver standalone (~15-30 minutes):

1. Downloads the TrueNAS ISO for the target version
2. Extracts kernel headers from the nested rootfs squashfs
3. Detects the real kernel version (e.g., `6.12.33-production+truenas`)
4. Compiles `hailo_pci.ko` with gcc-12 against those exact headers
5. Builds HailoRT userspace (libhailort, hailortcli) from source
6. Packages everything as a squashfs sysext image (without firmware)

The build runs on ubuntu-22.04 for GLIBC compatibility with TrueNAS (Debian Bookworm).

### Firmware Handling

Hailo-8 firmware is proprietary and this project does not redistribute it. Instead:

- At **install time**: firmware is downloaded from Hailo's S3 servers and injected into the sysext squashfs
- At **boot time**: the backed-up sysext already contains firmware — no network access needed
- The firmware version is determined from the release tag (e.g., `v25.10.2.1-hailo4.21.0` → version `4.21.0`)

### TrueNAS-Specific Details

- **Sysext activation** uses TrueNAS's middleware pattern (symlink in `/run/extensions/` + `systemd-sysext refresh`), not the standard `systemd-sysext merge`
- **Module loading** uses `insmod` instead of `modprobe` because `/lib/modules` is on a read-only ZFS dataset where `depmod` cannot write
- **Firmware** is injected into the sysext squashfs because `/lib/firmware` is also read-only

### Automated Updates

Two weekly GitHub Actions workflows monitor for updates:

- **Monday**: Checks for new TrueNAS SCALE releases → auto-triggers rebuild (new kernel may need recompiled module)
- **Wednesday**: Checks for new HailoRT releases → creates GitHub issue for manual review

## Scripts Reference

| Script | Purpose |
| --- | --- |
| `scripts/install.sh` | Downloads release, fetches firmware, injects into sysext, installs, sets up persistence |
| `scripts/restore.sh` | Uninstalls sysext, deregisters init script, cleans up persistent storage |
| `scripts/hailo-preinit.sh` | Boot-time script — activates sysext before apps start (also embedded in install.sh) |

## Important Notes

- The kernel module must match the exact TrueNAS kernel version. If you update TrueNAS, you need a matching sysext build. The PREINIT script handles reinstallation automatically, but a new build is needed if the kernel changed.
- The `hailort-drivers` repo uses the **`hailo8` branch** for Hailo-8 support. The `master` branch only supports Hailo-10/15.
- Secure Boot: The unsigned kernel module may require disabling Secure Boot.
- If firmware download fails during installation, the script aborts — the sysext will not be installed without firmware.

## Custom Builds

If you need a build for a TrueNAS version or HailoRT version that doesn't have a pre-built release, you can build your own using GitHub Actions — no local build environment needed.

### Fork and Build

1. **Fork** this repository on GitHub
2. Go to **Actions** > **Build Hailo Sysext** > **Run workflow**
3. Fill in the parameters:
   - **TrueNAS version** — e.g., `25.10.2.1` (must match an existing TrueNAS ISO on the download server)
   - **HailoRT driver version** — e.g., `4.21.0` (must match a tag in [hailo-ai/hailort-drivers](https://github.com/hailo-ai/hailort-drivers))
   - **Train name** — e.g., `Goldeye` (cosmetic, used in release title)
4. The workflow builds `hailo.raw` and creates a GitHub release in your fork (~15-30 min, ~5 min cached)
5. Use the install script from your fork's release, or download `hailo.raw` and install manually

### When to Build Custom

- **New TrueNAS release** not yet covered by a pre-built release (the Monday check workflow usually catches these within a week)
- **Different HailoRT version** — you want to test a newer or older driver version
- **Modified build** — you've forked the repo to change build options, add patches, etc.

### Version Defaults

The workflow inputs have defaults set to the most recently tested versions. The `version` and `.hailo-driver-version` files in the repo track what the automated workflows use. Update these if you want `workflow_dispatch` defaults to match your target.

## Architecture

See [docs/architecture.md](docs/architecture.md) for detailed build pipeline documentation, including the nested ISO squashfs extraction, kernel version detection, read-only filesystem constraints, and comparison with the NVIDIA sysext approach.

## License

MIT — see [LICENSE](LICENSE).

The Hailo-8 firmware downloaded during installation is proprietary and subject to Hailo's EULA.

## Credits

Build approach inspired by [truenas-nvidia-blackwell](https://github.com/scyto/truenas-nvidia-blackwell).

Hailo-8 driver source: [hailo-ai/hailort-drivers](https://github.com/hailo-ai/hailort-drivers) and [hailo-ai/hailort](https://github.com/hailo-ai/hailort).

## About This Project

This project was developed with the assistance of AI (Claude by Anthropic) via Claude Code. A human provided direction, reviewed outputs, and made decisions, but the implementation was AI-assisted.
