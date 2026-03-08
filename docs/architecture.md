# Build Pipeline Architecture

## Overview

This project builds a systemd-sysext package (`hailo.raw`) containing the Hailo-8 AI accelerator driver for TrueNAS SCALE. The sysext is a squashfs image that overlays `/usr/` via overlayfs when merged with `systemd-sysext merge`.

## Why Not scale-build?

The [NVIDIA sysext](https://github.com/scyto/truenas-nvidia-blackwell) uses TrueNAS's `scale-build` system because NVIDIA is integrated into TrueNAS's build manifest — it requires the full 126-package build to produce the rootfs chroot in which the NVIDIA installer runs.

Hailo-8 is **not** in the TrueNAS build manifest. It's a standard out-of-tree kernel module that only needs:
- Kernel headers matching the target TrueNAS kernel
- Standard build toolchain (gcc, make, cmake)
- HailoRT source code

This means we can skip scale-build entirely, reducing build time from ~5-6 hours to ~15-30 minutes.

## Build Pipeline

```
┌──────────────────────────────────────────────────────────────┐
│  Single GitHub Actions Job (~15-30 min)                      │
│                                                              │
│  1. Download TrueNAS ISO                                     │
│  2. Mount ISO → mount rootfs.squashfs → extract headers      │
│  3. Clone hailort-drivers@hailo8 → build hailo_pci.ko       │
│  4. Clone hailort@hailo8 → build libhailort + hailortcli    │
│  5. Download hailo8_fw.bin firmware                           │
│  6. Assemble sysext tree + depmod + extension-release        │
│  7. mksquashfs → hailo.raw (zstd compressed)                │
│  8. Create GitHub release                                    │
└──────────────────────────────────────────────────────────────┘
```

### Step Detail: Kernel Header Extraction

The most critical step is obtaining the exact kernel headers:

1. Download TrueNAS ISO from `https://download.truenas.com/TrueNAS-SCALE-{train}/{version}/`
2. Mount the ISO, find `live/filesystem.squashfs` (or similar path)
3. Mount the rootfs squashfs
4. Copy `/usr/src/linux-headers-{KVER}` — these contain the kernel config, Makefiles, and header files needed for out-of-tree module compilation
5. The exact `KVER` string (e.g., `6.12.6-production+truenas`) ensures the compiled module is ABI-compatible

### Step Detail: Kernel Module Build

```bash
cd hailort-drivers/linux/pcie
make KERNEL_DIR=/path/to/linux-headers-<KVER> all
```

This produces `hailo_pci.ko` — the single kernel module needed for Hailo-8 PCIe communication.

### Step Detail: HailoRT Build

```bash
cd hailort
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr ..
make -j$(nproc)
```

Produces `libhailort.so` (runtime library) and `hailortcli` (CLI tool).

## Sysext Structure

```
hailo.raw (squashfs, zstd compressed)
└── usr/
    ├── lib/
    │   ├── extension-release.d/
    │   │   └── extension-release.hailo    # ID=_any
    │   ├── modules/<KVER>/
    │   │   ├── extra/hailo_pci.ko
    │   │   └── modules.dep (+ other depmod output)
    │   ├── x86_64-linux-gnu/
    │   │   ├── libhailort.so → libhailort.so.4.x.x
    │   │   └── libhailort.so.4.x.x
    │   ├── firmware/hailo/
    │   │   └── hailo8_fw.bin
    │   ├── systemd/system/
    │   │   ├── hailo-load.service
    │   │   └── multi-user.target.wants/hailo-load.service
    │   └── udev/rules.d/
    │       └── 51-hailo-udev.rules
    └── bin/
        └── hailortcli
```

### extension-release

The file `usr/lib/extension-release.d/extension-release.hailo` contains `ID=_any`, matching the pattern used by TrueNAS's own NVIDIA sysext. This makes the extension compatible regardless of the OS ID string.

### Sysext Placement

Installed at `/usr/share/truenas/sysext-extensions/hailo.raw` — the same directory TrueNAS uses for its built-in NVIDIA sysext. The `systemd-sysext merge` command scans this directory.

## Persistence Mechanism

TrueNAS updates replace the rootfs, wiping any sysext placed in `/usr/`. The persistence mechanism has two layers:

### Layer 1: POSTINIT Script

A script registered with TrueNAS via `midclt call initshutdownscript.create`. Runs on every boot:

1. Finds backup at `/mnt/<pool>/.config/hailo/hailo.raw`
2. Compares SHA256 checksum with installed sysext
3. If different (TrueNAS updated) or missing: reinstalls from backup
4. Runs `systemd-sysext merge` and `modprobe hailo_pci`

### Layer 2: Persistent Storage

Config stored on a ZFS data pool (survives OS updates):

```
/mnt/<pool>/.config/hailo/
├── hailo.raw            # Backup of the sysext
└── hailo-postinit.sh    # The POSTINIT script itself
```

## Automated Version Monitoring

### TrueNAS Releases (Monday)

Queries `truenas/scale-build` GitHub tags for new `TS-25.10.*` stable releases. When found:
- Updates the `version` file
- Auto-triggers the build workflow

This is critical because a new TrueNAS release may ship a different kernel, requiring a recompiled `hailo_pci.ko`.

### HailoRT Releases (Wednesday)

Checks `hailo-ai/hailort-drivers` GitHub tags for newer versions. Creates an issue (does not auto-build) because:
- New driver versions should be tested before deployment
- The kernel module interface is stable across minor versions
- Users should opt-in to driver updates

## Comparison with NVIDIA Sysext

| Aspect | NVIDIA Sysext | Hailo Sysext |
|--------|--------------|--------------|
| Build system | Full scale-build (126 packages) | Standalone (kernel module + cmake) |
| Build time | ~5-6 hours (cached: ~1.5h) | ~15-30 minutes |
| Jobs | 2 (packages + update) | 1 |
| Caching | 3 granular caches (~4.2 GB) | ISO cache only |
| Retry logic | Yes (timeout recovery) | No (fast enough) |
| Kernel module | Part of NVIDIA .run installer | `make` against kernel headers |
| Userspace | NVIDIA apt packages | cmake build |
| scale-build submodule | Required | Not needed |
| MIG support | Yes (multi-instance GPU) | N/A |
