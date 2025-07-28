#!/usr/bin/env bash
set -euo pipefail

# ————————————————————————————————
# Configuration
# ————————————————————————————————

# Source root (your home directory)
SOURCE_ROOT="$HOME"

function showDriveMenu {
  drives=()
  for VOL in /Volumes/*; do
    drives+=($VOL)
}

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
#  --progress show per‑file progress
RSYNC_OPTS="-avh --progress"

# How many parallel jobs? Defaults to number of CPU cores.
MAX_JOBS=$(sysctl -n hw.ncpu)

# ————————————————————————————————
# 1) Find the first removable USB volume
# ————————————————————————————————
USB_MOUNT=""
USB_NAME=""
for VOL in /Volumes/*; do
  info=$(diskutil info "$VOL" 2>/dev/null || true)
  if echo "$info" | grep -qE'Removable Media:           Removable'; then
    USB_MOUNT="$VOL"
    break
  elif echo "$info" | grep -qE 'Protocol:           USB'; then
    USB_MOUNT="$VOL"
    break
  elif echo "$info" | grep -qE 'Device Location:           External'; then
    USB_MOUNT="$VOL"
    break
  fi
done

if [[ -z "$USB_MOUNT" ]]; then
  echo "No removable USB volume found under /Volumes."
  exit 1
fi

USB_NAME="$(diskutil info "$USB_MOUNT" | awk -F': *' '/Volume Name/ {print $2}')"

echo "Found USB drive at: $USB_MOUNT"

# ————————————————————————————————
# 2) Check if backup is wanted
# ————————————————————————————————

val=0

while [ "$val" -ne 1 ]; do
    echo "The USB Device selected is: $USB_NAME"
    echo "The user data selected for backup is from: $HOME"
    read -p "Do you want to continue? (y/n): " continue
    case "$continue" in 
        y)
            val=1
            ;;
        n)
            echo "Exiting"
            exit 1
            ;;
        *)
            echo "Must be 'y' or 'n'!"
            ;;
    esac
done

# ————————————————————————————————
# 3) Launch parallel rsync jobs
# ————————————————————————————————

# Create your user‑named folder on the USB
DEST_ROOT="${USB_MOUNT}/${USER}"
mkdir -p "$DEST_ROOT"

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
# 4) Done
# ————————————————————————————————
echo "Backup complete! Your files are in $DEST_ROOT"
echo "You can now safely eject the USB drive."
