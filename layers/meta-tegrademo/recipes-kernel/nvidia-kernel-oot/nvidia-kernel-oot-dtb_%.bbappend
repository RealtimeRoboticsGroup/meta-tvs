# Sets status = "disabled" on each node in DT_DISABLED_NODES, in the device
# trees the machine boots with.  UEFI uses the same device tree, so it skips
# those nodes too.
DT_DISABLED_NODES ??= ""

disable_dt_nodes() {
    for dtb in ${KERNEL_DEVICETREE}; do
        dtb=$(basename $dtb)
        for node in ${DT_DISABLED_NODES}; do
            fdtput -t s ${B}/$dtb $node status disabled
        done
    done
}

# Sets linux,msi-cpu on each node in DT_MSI_CPUS, given as <node>=<cpu>.  The
# PCIe controller routes all of its MSIs to that CPU (see the kernel's
# 0024-PCI-dwc-Let-the-device-tree-pick-the-CPU-for-a-contr.patch).
DT_MSI_CPUS ??= ""

set_dt_msi_cpus() {
    for dtb in ${KERNEL_DEVICETREE}; do
        dtb=$(basename $dtb)
        for entry in ${DT_MSI_CPUS}; do
            fdtput -t u ${B}/$dtb ${entry%=*} linux,msi-cpu ${entry#*=}
        done
    done
}

# do_compile is python, so these can't be appended to it.  They have to run
# before do_sign_dtbs.
do_compile[postfuncs] += "disable_dt_nodes set_dt_msi_cpus"
