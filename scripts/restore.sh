#!/usr/bin/env bash
# Restores the original state by removing hailo.raw sysext.
# Run this to completely remove the Hailo-8 driver extension.

set -euo pipefail

SYSEXT_DIR="/usr/share/truenas/sysext-extensions"
HAILO_RAW="${SYSEXT_DIR}/hailo.raw"
HAILO_BAK="${SYSEXT_DIR}/hailo.raw.bak"

echo "=== Removing Hailo-8 sysext ==="

# Unload module if present
if lsmod | grep -q hailo_pci; then
    echo "Unloading hailo_pci module..."
    rmmod hailo_pci || echo "WARNING: Failed to unload hailo_pci"
fi

# Remove hailo sysext symlink and refresh
echo "Removing hailo sysext..."
rm -f /run/extensions/hailo.raw
systemd-sysext refresh 2>/dev/null || true

# Make /usr writable
USR_DATASET=$(zfs list -H -o name /usr 2>/dev/null) || { echo "ERROR: Failed to find ZFS dataset for /usr (are you running as root?)"; exit 1; }
[ -z "$USR_DATASET" ] && { echo "ERROR: ZFS dataset for /usr is empty"; exit 1; }
zfs set readonly=off "${USR_DATASET}" || { echo "ERROR: Failed to make ${USR_DATASET} writable"; exit 1; }

# Remove hailo.raw (restore backup if it exists)
if [ -f "${HAILO_BAK}" ]; then
    echo "Restoring backup hailo.raw.bak..."
    mv "${HAILO_BAK}" "${HAILO_RAW}"
elif [ -f "${HAILO_RAW}" ]; then
    echo "Removing hailo.raw..."
    rm -f "${HAILO_RAW}"
fi

# Restore read-only
zfs set readonly=on "${USR_DATASET}" || echo "WARNING: Failed to restore ${USR_DATASET} to read-only"

echo ""
echo "=== Restore complete ==="

# --- Clean up persistence ---
echo ""
echo "=== Cleaning up persistence ==="

# Disable hailo-load service
systemctl disable hailo-load.service 2>/dev/null || true

# Deregister POSTINIT script
POSTINIT_ID=$(midclt call initshutdownscript.query 2>/dev/null \
    | python3 -c "
import sys, json
try:
    scripts = json.load(sys.stdin)
    for s in scripts:
        cmd = s.get('command', '') or s.get('script', '')
        if 'hailo-postinit' in cmd or '.config/hailo' in cmd:
            print(s['id'], end='')
            break
except Exception:
    pass
" 2>/dev/null) || true

if [ -n "$POSTINIT_ID" ]; then
    midclt call initshutdownscript.delete "$POSTINIT_ID" 2>/dev/null \
        && echo "POSTINIT script deregistered (id: ${POSTINIT_ID})" \
        || echo "WARNING: Failed to deregister POSTINIT script"
else
    echo "No POSTINIT script found to deregister"
fi

# Remove persistent config
for d in /mnt/*/.config/hailo; do
    if [ -d "$d" ]; then
        echo "Removing persistent config: $d"
        rm -rf "$d"
    fi
done

echo "Persistence cleanup complete"
