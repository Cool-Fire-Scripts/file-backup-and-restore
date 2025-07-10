#!/usr/bin/env bash
set -euo pipefail

# ————————————————————————————————
# Configuration
# ————————————————————————————————

# Source root (your home directory)
SOURCE_ROOT="$HOME"

# List of [source:destination‑subdir] pairs
TARGETS=(
  "$HOME/Desktop:Desktop"
  "$HOME/Documents:Documents"
  "$HOME/Downloads:Downloads"
  "$HOME/Pictures:Pictures"
  "$HOME/Movies:Videos"                           # macOS Movies → USB/Videos
  "$HOME/Music:Music"
  "$HOME/Library/Application Support/Firefox/Profiles:AppData/Firefox"
  "$HOME/Library/Application Support/Google/Chrome:AppData/Chrome"
  "$HOME/Library/Application Support/Microsoft Edge:AppData/Edge"
)

# rsync flags: 
#  -a   archive (recursive, perms, timestamps, symlinks)
#  -v   verbose
#  -h   human‑readable
#  -E   preserve extended attrs & resource forks on macOS
#  --delete  remove extraneous files from dest
#  --progress show per‑file progress
RSYNC_OPTS="-avhE --delete --progress"

# How many parallel jobs? Defaults to number of CPU cores.
MAX_JOBS=$(sysctl -n hw.ncpu)

# ————————————————————————————————
# 1) Find the first removable USB volume
# ————————————————————————————————
USB_MOUNT=""
for VOL in /Volumes/*; do
  # diskutil info accepts a mount point and prints "Removable Media: Yes" for USB sticks
  if diskutil info "$VOL" 2>/dev/null | grep -q "Removable Media: Yes"; then
    USB_MOUNT="$VOL"
    break
  fi
done

if [[ -z "$USB_MOUNT" ]]; then
  echo "No removable USB volume found under /Volumes."
  exit 1
fi

echo "Found USB drive at: $USB_MOUNT"

# Create your user‑named folder on the USB
DEST_ROOT="${USB_MOUNT}/${USER}"
mkdir -p "$DEST_ROOT"

# ————————————————————————————————
# 2) Launch parallel rsync jobs
# ————————————————————————————————
echo "Starting backups (up to $MAX_JOBS jobs in parallel)..."

# job counter
job_count=0

for PAIR in "${TARGETS[@]}"; do
  IFS=":" read -r SRC SUBDIR <<< "$PAIR"

  if [[ ! -d "$SRC" ]]; then
    echo "Skipping missing source: $SRC"
    continue
  fi

  DEST="${DEST_ROOT}/${SUBDIR}"
  mkdir -p "$DEST"

  echo "[$((job_count+1))] $SRC → $DEST"
  rsync $RSYNC_OPTS "$SRC/" "$DEST/" &

  (( job_count++ ))
  # if we've reached MAX_JOBS, wait for all before spawning more
  if (( job_count >= MAX_JOBS )); then
    wait
    job_count=0
  fi
done

# wait for any remaining background jobs
wait

# ————————————————————————————————
# 3) Done
# ————————————————————————————————
echo "Backup complete! Your files are in $DEST_ROOT"
echo "You can now safely eject the USB drive."
