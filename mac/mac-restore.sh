#!/usr/bin/env bash
set -euo pipefail

# ————————————————————————————————
# Configuration
# ————————————————————————————————

# Your local home
LOCAL_ROOT="$HOME"

# Same list of [local‑folder:usb‑subdir] pairs
TARGETS=(
  "$HOME/Desktop:Desktop"
  "$HOME/Documents:Documents"
  "$HOME/Downloads:Downloads"
  "$HOME/Pictures:Pictures"
  "$HOME/Movies:Videos"                           # USB/Videos → macOS Movies
  "$HOME/Music:Music"
  "$HOME/Library/Application Support/Firefox/Profiles:AppData/Firefox"
  "$HOME/Library/Application Support/Google/Chrome:AppData/Chrome"
  "$HOME/Library/Application Support/Microsoft Edge:AppData/Edge"
)

# rsync flags: archive, verbose, human‑readable sizes, macOS attrs, delete extraneous, show progress
RSYNC_OPTS="-avh --progress"

# Parallelism
MAX_JOBS=$(sysctl -n hw.ncpu)

# ————————————————————————————————
# 1) Locate the USB backup volume
# ————————————————————————————————
USB_MOUNT=""
USB_NAME=""
for VOL in /Volumes/*; do
  if diskutil info "$VOL" 2>/dev/null | grep -q "Removable Media:           Removable"; then
    USB_MOUNT="$VOL"
    break
  fi
done

if [[ -z "$USB_MOUNT" ]]; then
  echo "No removable USB volume found under /Volumes."
  exit 1
fi

USB_NAME=""$(diskutil info "$USB_MOUNT" | awk -F': *' '/Volume Name/ {print $2}')

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
# 3) Launch parallel restore jobs
# ————————————————————————————————

# Where on the USB your backups live
USB_ROOT="${USB_MOUNT}/${USER}"

if [[ ! -d "$USB_ROOT" ]]; then
  echo "Expected backup folder not found: $USB_ROOT"
  exit 1
fi

echo "Starting restore (up to $MAX_JOBS jobs in parallel)..."

job_count=0

for PAIR in "${TARGETS[@]}"; do
  IFS=":" read -r LOCAL_SUBDIR USB_SUBDIR <<< "$PAIR"

  SRC_USB="${USB_ROOT}/${USB_SUBDIR}"
  DEST_LOCAL="${LOCAL_SUBDIR}"

  if [[ ! -d "$SRC_USB" ]]; then
    echo "Skipping missing backup on USB: $SRC_USB"
    continue
  fi

  # Ensure local destination exists
  mkdir -p "$DEST_LOCAL"

  echo "Restoring $SRC_USB → $DEST_LOCAL"
  rsync $RSYNC_OPTS "$SRC_USB/" "$DEST_LOCAL/" &

  (( job_count++ ))
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
echo "Restore complete! Your files have been synced back to $LOCAL_ROOT"