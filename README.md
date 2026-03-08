# Hailo-8 AI Accelerator Sysext for TrueNAS SCALE

A systemd-sysext package that adds [Hailo-8](https://hailo.ai/) AI accelerator support to TrueNAS SCALE. Primarily useful for running [Frigate NVR](https://frigate.video/) with hardware-accelerated AI object detection.

## What's Included

The `hailo.raw` sysext contains:

| Component | Description |
|-----------|-------------|
| `hailo_pci.ko` | PCIe kernel module (compiled for exact TrueNAS kernel) |
| `libhailort.so` | HailoRT runtime library |
| `hailortcli` | HailoRT command-line tool |
| `hailo8_fw.bin` | Device firmware |
| `hailo-load.service` | Systemd service for automatic module loading |
| `51-hailo-udev.rules` | Udev rules for `/dev/hailo*` permissions |

## Quick Start

### Install

```bash
curl -fsSL https://github.com/scyto/truenas-hailo/releases/latest/download/install.sh | sudo bash
```

Or with explicit pool for persistence:

```bash
curl -fsSL https://github.com/scyto/truenas-hailo/releases/latest/download/install.sh -o install.sh
sudo bash install.sh --pool=fast
```

### Verify

```bash
# Check device is detected
ls -la /dev/hailo*

# Query firmware
hailortcli fw-control --identify
```

### Uninstall

```bash
curl -fsSL https://github.com/scyto/truenas-hailo/releases/latest/download/restore.sh | sudo bash
```

## Using with Frigate

After installing the sysext, configure your Frigate app to pass through the Hailo device:

1. In TrueNAS Apps, edit your Frigate configuration
2. Add device mapping: `/dev/hailo0:/dev/hailo0`
3. Configure Frigate's `detectors` section:

```yaml
detectors:
  hailo:
    type: hailo8
    device: /dev/hailo0
```

## How It Works

### Build Process

Unlike the [NVIDIA sysext](https://github.com/scyto/truenas-nvidia-blackwell) which requires the full TrueNAS `scale-build` pipeline (~5-6 hours), this project compiles the Hailo driver standalone (~15-30 minutes):

1. Downloads the TrueNAS ISO for the target version
2. Extracts kernel headers from the rootfs
3. Compiles `hailo_pci.ko` against those exact headers
4. Builds HailoRT userspace from source
5. Packages everything as a squashfs sysext image

### Persistence

TrueNAS updates wipe `/usr`, which would remove the sysext. The install script sets up:

- **Backup**: `hailo.raw` is copied to a persistent ZFS pool (`/mnt/<pool>/.config/hailo/`)
- **POSTINIT script**: Registered with TrueNAS, runs on every boot. Detects if the installed sysext differs from the backup (indicating a TrueNAS update) and reinstalls automatically.

### Automated Updates

Two weekly GitHub Actions workflows:

- **Monday**: Checks for new TrueNAS SCALE releases → auto-triggers rebuild
- **Wednesday**: Checks for new HailoRT releases → creates GitHub issue for manual review

## Important Notes

- The kernel module must match the exact TrueNAS kernel version. If you update TrueNAS, you need a matching sysext build. The POSTINIT script handles this automatically if a compatible build exists.
- The `hailort-drivers` repo uses the **`hailo8` branch** for Hailo-8 support. The `master` branch only supports Hailo-10/15.
- Secure Boot: The unsigned kernel module may require disabling Secure Boot.

## Building Locally

To trigger a build manually:

1. Go to **Actions** → **Build Hailo Sysext** → **Run workflow**
2. Set the TrueNAS version, HailoRT version, and train name
3. The workflow produces `hailo.raw` as both an artifact and a GitHub release

## Architecture

See [docs/architecture.md](docs/architecture.md) for detailed build pipeline documentation.

## License

MIT — see [LICENSE](LICENSE).

## Credits

Build approach inspired by [truenas-nvidia-blackwell](https://github.com/scyto/truenas-nvidia-blackwell).

Hailo-8 driver source: [hailo-ai/hailort-drivers](https://github.com/hailo-ai/hailort-drivers) and [hailo-ai/hailort](https://github.com/hailo-ai/hailort).
