# How It Works

## Build Process

Unlike the [NVIDIA sysext](https://github.com/scyto/truenas-nvidia-blackwell) which requires the full TrueNAS `scale-build` pipeline (~5-6 hours), this project compiles the Hailo driver standalone (~15-30 minutes):

1. Downloads the TrueNAS ISO for the target version
2. Extracts kernel headers from the nested rootfs squashfs
3. Detects the real kernel version (e.g., `6.12.33-production+truenas`)
4. Compiles `hailo_pci.ko` with gcc-12 against those exact headers
5. Builds HailoRT userspace (libhailort, hailortcli) from source
6. Packages everything as a squashfs sysext image (without firmware)

The build runs on ubuntu-22.04 for GLIBC compatibility with TrueNAS (Debian Bookworm).

## Firmware Handling

Hailo-8 firmware is proprietary and this project does not redistribute it. Instead:

- At **install time**: firmware is downloaded from Hailo's S3 servers and injected into the sysext squashfs
- At **boot time**: the backed-up sysext already contains firmware — no network access needed
- The firmware version is determined from the release tag (e.g., `v25.10.2.1-hailo4.21.0` → version `4.21.0`)

## TrueNAS-Specific Details

- **Sysext activation** uses TrueNAS's middleware pattern (symlink in `/run/extensions/` + `systemd-sysext refresh`), not the standard `systemd-sysext merge`
- **Module loading** uses `insmod` instead of `modprobe` because `/lib/modules` is on a read-only ZFS dataset where `depmod` cannot write
- **Firmware** is injected into the sysext squashfs because `/lib/firmware` is also read-only

## Automated Updates

Two weekly GitHub Actions workflows monitor for updates:

- **Monday**: Checks for new TrueNAS SCALE releases → auto-triggers rebuild (new kernel may need recompiled module)
- **Wednesday**: Checks for new HailoRT releases → creates GitHub issue for manual review

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
