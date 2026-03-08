#!/usr/bin/env bash
# TrueNAS POSTINIT script: reinstalls hailo.raw sysext after OS updates.
# Stored on persistent pool; registered via midclt during install.
# Idempotent — safe to run on every boot.
#
# NOTE: This script is also embedded inline in install.sh (heredoc).
# Keep both copies in sync when making changes.

set -uo pipefail

log() { echo "[hailo-postinit] $*"; }

# --- Find persistent config via glob ---
PERSIST_DIR=""
for d in /mnt/*/.config/hailo; do
    [ -d "$d" ] && PERSIST_DIR="$d" && break
done

if [ -z "$PERSIST_DIR" ]; then
    log "No persistent config found at /mnt/*/.config/hailo/, nothing to do"
    exit 0
fi

HAILO_RAW_BACKUP="${PERSIST_DIR}/hailo.raw"
SYSEXT_TARGET="/usr/share/truenas/sysext-extensions/hailo.raw"

if [ ! -f "$HAILO_RAW_BACKUP" ]; then
    log "No hailo.raw backup at ${HAILO_RAW_BACKUP}, nothing to do"
    exit 0
fi

# --- Compare checksums ---
if [ -f "$SYSEXT_TARGET" ]; then
    INSTALLED_SUM=$(sha256sum "$SYSEXT_TARGET" | awk '{print $1}')
    BACKUP_SUM=$(sha256sum "$HAILO_RAW_BACKUP" | awk '{print $1}')
    if [ "$INSTALLED_SUM" = "$BACKUP_SUM" ]; then
        log "hailo.raw already matches backup, skipping"
        exit 0
    fi
    log "hailo.raw differs from backup (update detected), reinstalling..."
else
    log "hailo.raw missing, installing from backup..."
fi

# --- Reinstall hailo.raw ---
log "Unmerging sysext..."
systemd-sysext unmerge 2>/dev/null || true

log "Making /usr writable..."
USR_DATASET=$(zfs list -H -o name /usr 2>/dev/null)
if [ -n "$USR_DATASET" ]; then
    zfs set readonly=off "$USR_DATASET"
fi

log "Copying hailo.raw from backup..."
if ! cp "$HAILO_RAW_BACKUP" "$SYSEXT_TARGET"; then
    log "ERROR: Failed to copy hailo.raw from backup"
    [ -n "$USR_DATASET" ] && zfs set readonly=on "$USR_DATASET" 2>/dev/null || true
    exit 1
fi

if [ -n "$USR_DATASET" ]; then
    zfs set readonly=on "$USR_DATASET"
fi

log "Merging sysext..."
systemd-sysext merge

log "Reloading systemd and loading Hailo module..."
systemctl daemon-reload
depmod -a || log "WARNING: depmod failed"
modprobe hailo_pci || log "WARNING: modprobe hailo_pci failed (device may not be present)"

log "hailo.raw reinstalled successfully"
exit 0
