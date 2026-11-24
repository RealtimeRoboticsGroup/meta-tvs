# meta-tvs

The image AOS runs on: an Orin Nano 8GB on a Seeed Studio J401 carrier, with
a mainline `PREEMPT_RT` kernel. It is built with Yocto Project tools and the
[meta-tegra](https://github.com/OE4T/meta-tegra) BSP layer, and started from
the [tegra-demo-distro](https://github.com/OE4T/tegra-demo-distro) reference
distribution.

- [docs/details.md](docs/details.md): how the image is put together (root
  filesystem, kernel, boot time, UEFI, camera debugging).
- [docs/realtime.md](docs/realtime.md): the real-time configuration
  (scheduling priorities, interrupts, networking, kernel patches and
  measuring latency).

Metadata layers are brought in as git submodules:

| Layer Repo           | Branch  | Description                                  |
| -------------------- | ------- | -------------------------------------------- |
| openembedded-core    | wrynose | OE-Core, pinned to Yocto 6.0.4               |
| bitbake              | 2.18    | BitBake, pinned to Yocto 6.0.4               |
| meta-tegra           | wrynose | Pinned L4T R39.2.1 / JetPack 7.2.1           |
| meta-tegra-community | wrynose | OE4T layer with additions from the community |
| meta-openembedded    | wrynose | OpenEmbedded layers                          |
| meta-virtualization  | wrynose | Virtualization layer                         |

Use the recorded submodule commits, not the moving branch tips:

```
git submodule update --init --recursive
```

## Building

### 1. Select a machine

Confirm the carrier and module, and set MACHINE accordingly.

| Board + Carrier                          | Command                                |
| ---------------------------------------- | -------------------------------------- |
| 8GB production module on a P3768 carrier | `export MACHINE=p3768-0000-p3767-0003` |
| Jetson Orin Nano Developer Kit           | `MACHINE=jetson-orin-nano-devkit-nvme` |

### 2. Build the image with bitbake

Warning: Always build on Linux with a case-sensitive build filesystem.

Note: this hasn't been tested yet with a fresh checkout, not everything might be captured yet.

Note: The build needs about 200G in `build/tmp`. To keep the download and shared
state caches elsewhere, create `build/conf/site.conf`:

```
DL_DIR = "/path/to/downloads"
SSTATE_DIR = "/path/to/sstate-cache"
```

Execute the build as

```
source layers/oe-init-build-env build
bitbake demo-image-base
```

The flash package is
`build/tmp/deploy/images/$MACHINE/demo-image-base-$MACHINE.rootfs.tegraflash-tar.zst`,
and the same package as a self-extracting flasher is
`demo-image-base-$MACHINE.rootfs.tegraflash-tar.run` next to it.

## Flashing

Perform the following steps to flash a new image on to your orin. This is required on the initial setup, or to apply changes to the kernel.

See also [docs/details.md](docs/details.md#booting).

### 1. Enter recovery mode

If you have a button header, hold RECOVERY while powering it on.

If you do not have a button header, then:

1. Power off the orin
2. Connect a jumper between the pins labeled "FC REC" and "GND" (pins 9 and 10)
3. Power on the orin, wait 2 seconds, disconnect the jumper

To verify the orin is in recovery mode, run `lsusb -d 0955:` on the flashing host. It should show `0955:7523`.

### 2. Flash the package

Copy the `.run` flasher to a directory on the flashing host's own disk (not `/tmp` or a USB stick), and from that directory run

```
sudo bash ./demo-image-base-$MACHINE.rootfs.tegraflash-tar.run
```

It unpacks the flash package next to itself, checks every file in it, waits for the orin in recovery mode, flashes it, and deletes the unpacked files again. It keeps the logs in a `flash-logs-*` directory next to itself, and says which packages to install if the host is missing any. Options after the name are passed to `initrd-flash`, e.g. `--erase-nvme`.

To flash from the `.tegraflash-tar.zst` instead, extract it into an empty directory.

Warning: Extracting a zst tarball from the Gnome GUI is prone to corruption! Instead, use a terminal to extract with

```
tar --zstd -xvf <flash_package>
```

Note: The flashing host needs `parted` and `udisks2` installed. Without them the
flash stops at `partprobe` after the orin has shown up as a USB disk.

From this new directory, run

```
sudo ./initrd-flash
```

### 3. Verify the flash worked

After a successful flash, you can connect to your orin over ethernet:

1. Ensure that the host has an IP address and netmask assigned for the ethernet adapter (e.g. 10.18.68.50/24)
2. Plug in an ethernet cable to both the orin and the host machine
3. Verify that the orin is visible to the host: `ping 10.18.68.101`
4. ssh to the orin: `ssh pi@10.18.68.101` with password `raspberry`

You can also use a USB serial cable to see the boot logs on the orin:

1. Connect a USB serial cable from the host, to the orin.
   * Connect the TX wire of the cable to the RX pin of the header (pin 3)
   * Connenct the RX wire to the TX pin (pin 4)
   * Connect the ground wire to the ground pin (pin 7)
2. Run miniterm as
   `python3 /usr/lib/python3/dist-packages/serial/tools/miniterm.py /dev/ttyUSB0 115200`

## AOS compatibility

This image pins CUDA 13.2, OpenCV 4.13 and TensorRT 10.16. AOS has to be
rebuilt against a sysroot exported from this image. Missing
`libcudart.so.12` or `libopencv_*.so.411` on the Orin indicates old binaries;
reflashing alone does not fix them.

Export it with `compilers/buildify_yocto_image.py` in AOS, which turns the
built root filesystem into the `arm64_debian_sysroot` Bazel module.

TensorRT engines are tied to the TensorRT version which built them. Rebuild
them on the Orin with `trtexec` after flashing, with nothing else using the GPU
while it runs. The flags AOS's `yolo` needs are in the YOLO section of
`frc/vision/README.md` in AOS.

The 8GB module has little memory to spare with four cameras running. Realtime
AOS processes lock every library they load into RAM, and the libraries in this
release are large (`libnvinfer.so` is 860 MB, `libcublasLt.so` 600 MB,
`libcufft.so` 290 MB), so a process should only link what it uses.

## Cameras

`camera.rules` names the UVC cameras `/dev/videoa` through `/dev/videod` by
USB port, for two alternative four-port hub layouts. Use one layout at a time
and verify the names against the physical camera calibrations. Unknown USB
layouts intentionally get no name; capture-device enumeration order is not a
stable calibration identifier.

For UVC driver debugging, see
[docs/details.md](docs/details.md#uvc-camera-debugging).
