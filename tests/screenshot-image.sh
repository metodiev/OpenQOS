#!/bin/bash
#
# Boot an OpenQOS image under QEMU and capture its screen.
#
#   sudo tests/screenshot-image.sh <image.qcow2|image.iso> [timeout-seconds]
#
# Run inside the Fedora development VM. Frames land in $WORK/shots as PPM files,
# and the path is printed at the end.
#
# Why this exists
# ---------------
# The development VM has no GPU and no /dev/dri, so nothing running inside it can
# draw anything: Plasma, Plymouth and the login manager all render into nothing.
# That made every visual claim about this distribution unverifiable — the desktop
# layout, the wallpaper, the boot splash and the login screen could only ever be
# described, never seen.
#
# QEMU emulates a virtio GPU, so a guest booted here *does* have /dev/dri and does
# draw. Its screen is then read with the QEMU monitor's screendump, which needs no
# display on the host and works over a unix socket.
#
# Two details that are easy to get wrong:
#
#   * The firmware. QEMU 10 requires each pflash unit to be the full 64 MB the virt
#     machine declares, and refuses the 3 MB QEMU_EFI.fd with
#     "cfi.pflash01 device ... requires 67108864 bytes". Fedora ships pre-padded
#     pflash images; use those.
#
#   * Progress detection. The serial console cannot be trusted: systemd stops
#     logging there once the console moves, and a graphical greeter writes nothing
#     to it at all. So progress is judged from the framebuffer, and by *content*,
#     not file size — a PPM is width*height*3 bytes whether it holds a wallpaper or
#     one flat colour, so only its compressed size distinguishes blank from drawn.
#
# The source image is never booted: a boot writes to the disk, and a built artefact
# must not change because someone looked at it.

set -euo pipefail

if [[ $# -lt 1 ]]; then
	echo "usage: screenshot-image.sh <image> [timeout-seconds]" >&2
	exit 2
fi

image="$1"
timeout_seconds="${2:-1800}"
work="${WORK:-/var/tmp/openqos-screenshot}"
# A host port forward lets you SSH into the guest for diagnostics while it is up,
# which is the only way to ask a *running* image what it thinks. Off unless asked
# for: the default port collides with Lima's own forwarding, and a boot that cannot
# start because a port is busy is a poor trade for a convenience.
ssh_port="${SSH_PORT:-}"
network_forward=""
if [[ -n "${ssh_port}" ]]; then
	network_forward=",hostfwd=tcp::${ssh_port}-:22"
fi

# VNC is not used to look at anything; QEMU needs a display device for screendump to
# have a surface to read, and a VNC server is the cheapest one that needs no host
# display. The port is configurable because a stale guest holding it makes the next
# boot fail with "Failed to find an available port" and no hint as to why.
vnc_display="${VNC_DISPLAY:-9}"

# How many drawn frames to collect before stopping. Two is enough to prove the screen
# is graphical; more is useful when something *changes* on screen and the steady state
# is what matters — a greeter painting its wallpaper after its own default, or an
# autologin handing over to a desktop session.
graphical_frames="${GRAPHICAL_FRAMES:-2}"

readonly uefi="/usr/share/edk2/aarch64/QEMU_EFI-pflash.qcow2"
readonly uefi_vars="/usr/share/edk2/aarch64/QEMU_EFI-qemuvars-pflash.qcow2"

for tool in qemu-system-aarch64 qemu-img python3; do
	command -v "${tool}" >/dev/null 2>&1 || {
		echo "error: ${tool} is required." >&2
		exit 1
	}
done
for firmware in "${uefi}" "${uefi_vars}"; do
	[[ -f "${firmware}" ]] || {
		echo "error: ${firmware} is missing." >&2
		echo "       Install edk2-aarch64." >&2
		exit 1
	}
done
[[ -f "${image}" ]] || {
	echo "error: ${image} not found." >&2
	exit 1
}

rm -rf -- "${work}"
mkdir -p -- "${work}/shots"

echo "Copying the image (the artefact itself is never booted)"
if [[ "${image}" == *.qcow2 ]]; then
	cp --reflink=auto -- "${image}" "${work}/disk.qcow2"
	disk_args=(-drive "if=virtio,format=qcow2,file=${work}/disk.qcow2")
else
	cp --reflink=auto -- "${image}" "${work}/image.iso"
	disk_args=(-drive "if=virtio,format=raw,readonly=on,file=${work}/image.iso")
fi
cp -- "${uefi}" "${work}/QEMU_EFI.qcow2"
cp -- "${uefi_vars}" "${work}/QEMU_VARS.qcow2"

qemu-system-aarch64 \
	-M virt -cpu max -smp 4 -m 4096 \
	-drive "if=pflash,format=qcow2,readonly=on,file=${work}/QEMU_EFI.qcow2" \
	-drive "if=pflash,format=qcow2,file=${work}/QEMU_VARS.qcow2" \
	-device virtio-gpu-pci \
	-device virtio-keyboard-pci \
	-device virtio-tablet-pci \
	-device virtio-net-pci,netdev=n0 \
	-netdev "user,id=n0${network_forward}" \
	"${disk_args[@]}" \
	-vnc "127.0.0.1:${vnc_display}" \
	-serial "file:${work}/serial.log" \
	-monitor "unix:${work}/monitor.sock,server,nowait" \
	-pidfile "${work}/qemu.pid" \
	-daemonize

echo "QEMU running as pid $(cat "${work}/qemu.pid"); watching the screen for up to ${timeout_seconds}s"
echo "Serial console: ${work}/serial.log"

cleanup() {
	if [[ -f "${work}/qemu.pid" ]]; then
		# Kill by PID. A name-based match would match this script's own command
		# line and take the session down with it.
		kill "$(cat "${work}/qemu.pid")" 2>/dev/null || true
	fi
}
trap cleanup EXIT

python3 - "${work}" "${timeout_seconds}" "${graphical_frames}" <<'PY'
"""Capture the guest's screen until it is visibly drawing something."""

import os
import socket
import sys
import time
import zlib

work, deadline = sys.argv[1], int(sys.argv[2])
want_graphical = int(sys.argv[3])
monitor = os.path.join(work, "monitor.sock")
shots = os.path.join(work, "shots")

# Two thresholds, because "not blank" is not the same as "graphical". A text console
# is mostly black with thin light glyphs and compresses to tens of kilobytes. A
# wallpaper is a full-screen gradient and compresses to a great deal more, so the
# gap between the two is wide enough to tell them apart without decoding the image.
blank_threshold = 5_000
text_threshold = 80_000


def content_size(path):
    """Compressed pixel size: the only cheap way to tell blank from drawn."""
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except OSError:
        return 0
    parts = data.split(b"\n", 3)
    if len(parts) < 4 or parts[0] != b"P6":
        return 0
    return len(zlib.compress(parts[3], 6))


start = time.time()
frames = 0
graphical = 0

while time.time() - start < deadline:
    elapsed = int(time.time() - start)
    path = os.path.join(shots, f"screen-{elapsed:04d}.ppm")

    try:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.connect(monitor)
        time.sleep(0.2)
        connection.recv(65536)
        connection.sendall(f"screendump {path}\n".encode())
        time.sleep(2.0)
        connection.recv(65536)
        connection.close()
    except OSError as error:
        print(f"[{elapsed:5}s] monitor error: {error}", flush=True)
        time.sleep(30)
        continue

    size = content_size(path)
    frames += 1
    if size > text_threshold:
        graphical += 1
        print(f"[{elapsed:5}s] frame {frames}: content {size} bytes  <- graphical", flush=True)
        if graphical >= want_graphical:
            print(f"stopping: {graphical} drawn frames collected", flush=True)
            break
    elif size > blank_threshold:
        print(f"[{elapsed:5}s] frame {frames}: content {size} bytes  (console)", flush=True)
    else:
        print(f"[{elapsed:5}s] frame {frames}: content {size} bytes  (blank)", flush=True)

    time.sleep(20)

print(f"done: {frames} frames, {graphical} of them graphical", flush=True)
PY

echo "Frames: ${work}/shots"
mapfile -t frames < <(find "${work}/shots" -name '*.ppm' | sort)
printf '%s\n' "${frames[@]: -5}"
echo "total frames: ${#frames[@]}"
