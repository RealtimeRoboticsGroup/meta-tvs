# A "run" conversion: the flash package as a self-extracting flasher, made by
# scripts/make-flash-run.  "sudo bash ./<image>.tegraflash-tar.run" unpacks it
# next to itself with tar, checks every unpacked file, waits for the Jetson in
# recovery mode and runs initrd-flash.
#
# Archive managers get the root filesystem's sparse file wrong without saying
# so, and nothing after that checks it, so the root filesystem then fails to
# mount on the Jetson.

CONVERSIONTYPES += "run"

# zstd threads for the flasher.  Each takes about 650 MiB at -21.
FLASH_RUN_THREADS ?= "8"

CONVERSION_CMD:run = "FLASH_RUN_THREADS=${FLASH_RUN_THREADS} ${TD_DISTRO_LAYERDIR}/scripts/make-flash-run ${IMAGE_NAME}.${type} ${IMAGE_NAME}.${type}.run ${MACHINE}"
CONVERSION_DEPENDS_run = "zstd-native"

# Rebuild the flasher when the scripts change.
do_image_tegraflash_tar[file-checksums] += "${TD_DISTRO_LAYERDIR}/scripts/make-flash-run:True ${TD_DISTRO_LAYERDIR}/scripts/flash-run-header.sh:True"
