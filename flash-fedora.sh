#!/usr/bin/env bash
# flash-fedora.sh — interactive Fedora ISO download, verify, USB flash.
# Handles both filename conventions:
#   Fedora-Workstation-Live-45-1.4.x86_64.iso   (Fedora 45 and later)
#   Fedora-Workstation-Live-x86_64-45-1.4.iso   (older releases)
# 2>/dev/null is used only for expected umount noise.

set +e
set +u
set +o pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run]"
      echo "  --dry-run   stop before dd"
      exit 0 ;;
  esac
done

P="[flash-fedora]"
DEFAULT_VER="45"
DEFAULT_ED="Workstation"
DEFAULT_BUILD="1.4"
DEFAULT_ARCH="x86_64"

echo "$P Pre-authenticating sudo..."
sudo -v || { echo "$P Sudo failed."; exit 1; }
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null' EXIT

echo "$P Interactive setup (Enter accepts default)"
read -r -p "$P Fedora version [$DEFAULT_VER]: " VER; VER=${VER:-$DEFAULT_VER}
read -r -p "$P Edition [$DEFAULT_ED]: " ED; ED=${ED:-$DEFAULT_ED}
read -r -p "$P Build [$DEFAULT_BUILD]: " BUILD; BUILD=${BUILD:-$DEFAULT_BUILD}
read -r -p "$P Architecture [$DEFAULT_ARCH]: " ARCH; ARCH=${ARCH:-$DEFAULT_ARCH}

ISO_NEW="Fedora-${ED}-Live-${VER}-${BUILD}.${ARCH}.iso"
ISO_OLD="Fedora-${ED}-Live-${ARCH}-${VER}-${BUILD}.iso"
BASE_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/${VER}/${ED}/${ARCH}/iso"

ISO_FILE=""
for cand in "$ISO_NEW" "$ISO_OLD"; do
  if [ -f "$cand" ]; then
    ISO_FILE="$cand"
    echo "$P Found existing: $cand ($(stat -c %s "$cand") bytes)"
    break
  fi
done

if [ -z "$ISO_FILE" ]; then
  for cand in "$ISO_NEW" "$ISO_OLD"; do
    URL="$BASE_URL/$cand"
    echo "$P Trying $URL"
    until curl -fL -C - --retry 20 --retry-delay 10 --speed-limit 500 --speed-time 30 -o "$cand" "$URL"; do
      echo "$P Stalled. Resuming in 5s (Ctrl-C to abort)."
      sleep 5
    done
    if [ -f "$cand" ]; then ISO_FILE="$cand"; break; fi
  done
fi

if [ -z "$ISO_FILE" ]; then
  echo "$P Both patterns 404. Check $BASE_URL/"
  exit 1
fi

echo "$P Locating checksum (best effort)"
ISO_BASE="${ISO_FILE%.iso}"
for c in "${ISO_BASE}-CHECKSUM" "Fedora-${ED}-${VER}-${BUILD}-${ARCH}-CHECKSUM" "Fedora-${ED}-${VER}-${BUILD}.${ARCH}-CHECKSUM"; do
  if curl -fL -s -o "/tmp/fedora-checksum.$$" "$BASE_URL/$c"; then
    if [ -s "/tmp/fedora-checksum.$$" ] && ! head -c 400 "/tmp/fedora-checksum.$$" | grep -qi '<html'; then
      CHECKSUM_FILE="/tmp/fedora-checksum.$$"
      echo "$P Got checksum: $c"
      break
    fi
  fi
done

VERIFY_OK=0
if [ -n "$CHECKSUM_FILE" ]; then
  if sha256sum -c "$CHECKSUM_FILE" --ignore-missing 2>/dev/null | grep -q ': OK'; then
    VERIFY_OK=1; echo "$P Checksum PASSED"
  else
    echo "$P Checksum FAILED"
    read -r -p "$P Continue anyway? [y/N]: " a
    case "$a" in y|Y) VERIFY_OK=1 ;; esac
  fi
  rm -f "$CHECKSUM_FILE"
else
  echo "$P No checksum file reachable."
  read -r -p "$P Paste SHA-256 (Enter to skip): " MANUAL_HASH
  if [ -n "$MANUAL_HASH" ]; then
    echo "$MANUAL_HASH  $ISO_FILE" | sha256sum -c - && VERIFY_OK=1
  else
    VERIFY_OK=1
  fi
fi

if [ "$VERIFY_OK" -ne 1 ]; then
  echo "$P Refusing to flash unverified image."
  exit 1
fi

echo "$P Loop-mounting..."
MDIR=$(mktemp -d)
if sudo mount -o loop,ro "$ISO_FILE" "$MDIR"; then
  if [ -f "$MDIR/LiveOS/squashfs.img" ] || [ -f "$MDIR/images/install.img" ]; then
    echo "$P Payload structure OK"
  else
    echo "$P WARN: payload markers missing"
  fi
  sudo umount "$MDIR"
else
  echo "$P WARN: loop-mount failed; continuing"
fi
rmdir "$MDIR" 2>/dev/null

echo "$P Available disks:"
lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL

ROOT_SRC=$(findmnt -no SOURCE / 2>/dev/null)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -1)
[ -n "$ROOT_DISK" ] && echo "$P Root is on /dev/$ROOT_DISK (will refuse)"

TARGET=""
while [ -z "$TARGET" ]; do
  read -r -p "$P Target disk (e.g. sdb): " in
  in=${in#/dev/}
  [ -z "$in" ] && { echo "$P No input."; continue; }
  [ ! -b "/dev/$in" ] && { echo "$P /dev/$in not a block device."; continue; }
  T=$(lsblk -dno TYPE "/dev/$in")
  [ "$T" != "disk" ] && { echo "$P /dev/$in is '$T', not 'disk'."; continue; }
  [ -n "$ROOT_DISK" ] && [ "$in" = "$ROOT_DISK" ] && { echo "$P /dev/$in hosts root. Refusing."; continue; }
  TR=$(lsblk -dno TRAN "/dev/$in")
  if [ "$TR" != "usb" ]; then
    echo "$P WARN: transport is '$TR', not 'usb'."
    read -r -p "$P Continue? [y/N]: " a
    case "$a" in y|Y) TARGET="$in" ;; *) continue ;; esac
  else
    TARGET="$in"
  fi
done

echo "$P Target: /dev/$TARGET"
lsblk "/dev/$TARGET"
echo "$P WARNING: all data on /dev/$TARGET will be destroyed."
read -r -p "$P Type ERASE to confirm: " WORD
[ "$WORD" != "ERASE" ] && { echo "$P Aborted."; exit 0; }

for part in $(lsblk -lno NAME "/dev/$TARGET" | tail -n +2); do
  sudo umount "/dev/$part" 2>/dev/null && echo "$P Unmounted /dev/$part"
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "$P Dry run: would run dd if=$ISO_FILE of=/dev/$TARGET bs=4M status=progress oflag=sync conv=fsync"
  exit 0
fi

echo "$P Writing..."
sudo dd if="$ISO_FILE" of="/dev/$TARGET" bs=4M status=progress oflag=sync conv=fsync
RC=$?
sync
if [ "$RC" -ne 0 ]; then echo "$P dd failed ($RC)."; exit 1; fi

echo "$P Flash complete."
lsblk "/dev/$TARGET"
