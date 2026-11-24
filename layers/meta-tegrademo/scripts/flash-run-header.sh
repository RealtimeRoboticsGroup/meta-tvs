#!/bin/bash
# Flashes @IMAGE@ onto a Jetson (@MACHINE@).
#
# Put the Jetson in recovery mode and connect it over USB, then run:
#   sudo bash ./@RUNNAME@
# Options after the name are passed to initrd-flash, e.g. --erase-nvme.
#
# The flash package is appended to this script.  It is unpacked into a
# directory next to this file, checked, flashed and deleted again; the logs
# are kept in a flash-logs-* directory next to this file.

[ -n "$BASH_VERSION" ] || exec bash "$0" "$@"

set -euo pipefail

PAYLOAD_SIZE=@PAYLOAD_SIZE@
# Space the unpacked package takes, not counting the holes in sparse files.
DATA_SIZE=@DATA_SIZE@

die() {
    echo >&2
    echo "ERROR: $*" >&2
    exit 1
}

# Prints the product ID of each NVIDIA device in recovery mode.
recovery_devices() {
    local d
    for d in /sys/bus/usb/devices/*; do
        [ "$(cat "$d/idVendor" 2>/dev/null)" = 0955 ] || continue
        case "$(cat "$d/idProduct" 2>/dev/null)" in
            7[0-9a-f]23) cat "$d/idProduct" ;;
        esac
    done
}

check_tools() {
    local missing=() tool
    for tool in zstd:zstd tar:tar sha256sum:coreutils python3:python3 \
                udisksctl:udisks2 partprobe:parted sgdisk:gdisk \
                blockdev:util-linux udevadm:udev; do
        command -v "${tool%%:*}" >/dev/null || missing+=("${tool#*:}")
    done
    python3 -c 'import yaml' 2>/dev/null || missing+=(python3-yaml)
    if [ ${#missing[@]} -gt 0 ]; then
        die "Missing tools.  Install them with:
  sudo apt install ${missing[*]}"
    fi
}

# The package holds the root filesystem as a sparse file, so the directory it
# is unpacked into has to support them.  exFAT and NTFS (e.g. a USB stick)
# don't, and tmpfs would hold it all in memory.
check_space() {
    local fstype avail
    fstype=$(stat -f -c %T "$here")
    case "$fstype" in
        tmpfs|ramfs)
            die "$here is in memory ($fstype).  Move $(basename "$self") to your home directory and run it from there." ;;
    esac
    truncate -s 64M "$work/.sparse-test"
    if [ "$(stat -c %b "$work/.sparse-test")" -gt 1024 ]; then
        die "$here is on a filesystem without sparse files ($fstype).  Move $(basename "$self") to your home directory and run it from there."
    fi
    rm "$work/.sparse-test"
    avail=$(df -B1 --output=avail "$here" | tail -n 1)
    if [ "$avail" -lt $((DATA_SIZE + (1 << 30))) ]; then
        die "Not enough space in $here: unpacking needs $(((DATA_SIZE >> 30) + 1)) GiB and $((avail >> 30)) GiB is free."
    fi
}

save_logs() {
    local f
    [ -d "$work" ] || return 0
    for f in "$work"/log.initrd-flash.* "$work"/device-logs-*; do
        [ -e "$f" ] && cp -r "$f" "$logdir/"
    done
    if [ -n "${SUDO_UID:-}" ]; then
        chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$logdir"
    fi
}

cleanup() {
    save_logs || true
    rm -rf "$work"
}

main() {
    self=$(readlink -f "$0")
    here=$(dirname "$self")

    if [ "$(id -u)" -ne 0 ]; then
        die "Flashing needs root.  Run it with:
  sudo bash $0"
    fi

    logdir=$(mktemp -d -p "$here" "flash-logs-$(date +%Y%m%d-%H%M%S)-XXXX")
    chmod 755 "$logdir"
    exec > >(tee -a "$logdir/flash.log") 2>&1
    echo "Flashing @IMAGE@; logging to $logdir"
    set -x

    check_tools

    # The package starts straight after this script's last line, so if the
    # file is short, that line isn't where the package should start.
    local size
    size=$(stat -c %s "$self")
    if [ "$size" -le "$PAYLOAD_SIZE" ] ||
       [ "$(head -c $((size - PAYLOAD_SIZE)) "$self" | tail -n 1)" != 'exit $?' ]; then
        die "$(basename "$self") is incomplete ($size bytes).  Download it again."
    fi

    work=$(mktemp -d -p "$here" .flash-XXXXXX)
    # Ctrl-C also kills tee, and writing to it then would kill this script
    # before it cleans up, so stop tracing and ignore SIGPIPE first.
    trap '{ set +x; } 2>/dev/null; trap "" PIPE; cleanup' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    check_space

    # The release page lists the sha256 of this file.  It isn't checked here:
    # zstd's checksum catches a corrupt download while unpacking, and the
    # unpacked files are checked below.
    echo "== Unpacking into $work =="
    if ! tail -c "$PAYLOAD_SIZE" "$self" | zstd -dc | tar -x --no-same-owner -C "$work"; then
        die "Unpacking failed; $(basename "$self") may be corrupt.  Download it again."
    fi

    echo "== Checking the unpacked files =="
    cat > "$work/.SHA256SUMS" <<'EOF'
@SHA256SUMS@
EOF
    if ! (cd "$work" && sha256sum --quiet -c .SHA256SUMS); then
        die "The unpacked files don't match.  Check the disk in $here."
    fi

    if [ -z "$(recovery_devices)" ]; then
        set +x
        echo
        echo "Waiting for the Jetson in recovery mode.  Hold RECOVERY while powering"
        echo "it on, with its USB-C port connected to this computer."
        while [ -z "$(recovery_devices)" ]; do
            sleep 1
        done
        set -x
    fi
    echo "Found 0955:$(recovery_devices | head -n 1) in recovery mode"

    echo "== Flashing =="
    local rc=0
    (cd "$work" && ./initrd-flash "$@") || rc=$?
    set +x
    echo
    if [ "$rc" -ne 0 ]; then
        die "Flashing failed (exit status $rc).  Logs are in $logdir"
    fi
    echo "Flashing finished.  Logs are in $logdir"
}

main "$@"
exit $?
