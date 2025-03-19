#!/bin/bash

# Copyright (c) 2011-2021, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


#
# This script applies the binaries to the rootfs dir pointed to by
# LDK_ROOTFS_DIR variable.
#

set -e

success=0

# show the usages text
function ShowUsage {
    local ScriptName=$1

    echo "Use: $1 [--bsp|-b PATH] [--root|-r PATH] [--target-overlay] [--product-id|-p PRODUCT_NAME] [--help|-h]"
cat <<EOF
    This script installs tegra binaries
    Options are:
    --bsp|-b PATH
                   bsp location (bsp, readme, installer)
    --root|-r PATH
                   install toolchain to PATH
    --target-overlay|-t
                   untar NVIDIA target overlay (.tbz2) instead of
				   pre-installing them as Debian packages
    --product-id|-p PRODUCT_NAME
                   Product Name (supported products are: bagheera3, b3_v1, b3_v2, octo)
    --help|-h
                   show this help
    --no-debs
		   do not create kernel and dtb debians for ota upgrade
EOF
}

function ShowDebug {
    echo "SCRIPT_NAME     : $SCRIPT_NAME"
    echo "DEB_SCRIPT_NAME : $DEB_SCRIPT_NAME"
    echo "LDK_ROOTFS_DIR  : $LDK_ROOTFS_DIR"
    echo "BOARD_NAME      : $TARGET_BOARD"
}

function ReplaceText {
	sed -i "s/$2/$3/" $1
	if [ $? -ne 0 ]; then
		echo "Error while editing a file. Exiting !!"
		exit 1
	fi
}

function AddSystemGroup {
	gids=($(cut -d: -f3 ./etc/group))
	for gid in {999..100}; do
		if [[ ! " ${gids[*]} " =~ " ${gid} " ]]; then
			echo "${1}:x:${gid}:" >> ./etc/group
			echo "${1}:!::" >> ./etc/gshadow
			break
		fi
	done
}

# if the user is not root, there is not point in going forward
THISUSER=`whoami`
if [ "x$THISUSER" != "xroot" ]; then
    echo "This script requires root privilege"
    exit 1
fi


# script name
SCRIPT_NAME=`basename $0`

# apply .deb script name
DEB_SCRIPT_NAME="nv-apply-debs.sh"

# empty root and no debug
DEBUG=

# flag used to switch between legacy overlay packages and debians
# default is debians, but can be switched to overlay by setting to "true"
USE_TARGET_OVERLAY_DEFAULT="true"

UPDATE_DEBS="true"

# parse the command line first
TGETOPT=`getopt -n "$SCRIPT_NAME" --longoptions help,bsp:,debug,target-overlay,root:,product-id:,no-debs -o b:dhr:b:t:p: -- "$@"`

if [ $? != 0 ]; then
    echo "Terminating... wrong switch"
    ShowUsage "$SCRIPT_NAME"
    exit 1
fi

eval set -- "$TGETOPT"

while [ $# -gt 0 ]; do
    case "$1" in
	-r|--root) LDK_ROOTFS_DIR="$2"; shift ;;
	-h|--help) ShowUsage "$SCRIPT_NAME"; exit 1 ;;
	-d|--debug) DEBUG="true" ;;
	-t|--target-overlay) TARGET_OVERLAY="true" ;;
	-b|--bsp) BSP_LOCATION_DIR="$2"; shift ;;
	-p|--product-id) PRODUCT_NAME="$2"; shift ;;
	--no-debs) UPDATE_DEBS="false" ;;
	--) shift; break ;;
	-*) echo "Terminating... wrong switch: $@" >&2 ; ShowUsage "$SCRIPT_NAME"; exit 1 ;;
    esac
    shift
done

if [ $# -gt 0 ]; then
    ShowUsage "$SCRIPT_NAME"
    exit 1
fi

# done, now do the work, save the directory
LDK_DIR=$(cd `dirname $0` && pwd)

# use default rootfs dir if none is set
if [ -z "$LDK_ROOTFS_DIR" ]; then
    LDK_ROOTFS_DIR="${LDK_DIR}/rootfs"
fi

echo "Using rootfs directory of: ${LDK_ROOTFS_DIR}"

install -o 0 -g 0 -m 0755 -d "${LDK_ROOTFS_DIR}"

# get the absolute path, for LDK_ROOTFS_DIR.
# otherwise, tar behaviour is unknown in last command sets
TOP=$PWD
cd "${LDK_ROOTFS_DIR}"
LDK_ROOTFS_DIR="$PWD"
cd "$TOP"

if [ ! "$(find "${LDK_ROOTFS_DIR}/etc/passwd" -group root -user root)" ]; then
	echo "||||||||||||||||||||||| ERROR |||||||||||||||||||||||"
	echo "-----------------------------------------------------"
	echo "1. The root filesystem, provided with this package,"
	echo "   has to be extracted to this directory:"
	echo "   ${LDK_ROOTFS_DIR}"
	echo "-----------------------------------------------------"
	echo "2. The root filesystem, provided with this package,"
	echo "   has to be extracted with 'sudo' to this directory:"
	echo "   ${LDK_ROOTFS_DIR}"
	echo "-----------------------------------------------------"
	echo "Consult the Development Guide for instructions on"
	echo "extracting and flashing your device."
	echo "|||||||||||||||||||||||||||||||||||||||||||||||||||||"
	exit 1
fi

# assumption: this script is part of the BSP
#             so, LDK_DIR/nv_tegra always exist
LDK_NV_TEGRA_DIR="${LDK_DIR}/nv_tegra"
LDK_KERN_DIR="${LDK_DIR}/kernel"
LDK_TOOLS_DIR="${LDK_DIR}/tools"
LDK_BOOTLOADER_DIR="${LDK_DIR}/bootloader"
DEB_EXTRACTOR="${LDK_TOOLS_DIR}/l4t_extract_deb.sh"
LDK_NV_LOW_LEVEL_BIN_PATH=$LDK_BOOTLOADER_DIR/nv_l4t_low_level_bins

if [ -z $PRODUCT_NAME ];then
	echo "WARNING: PRODUCT NAME is not defined"
	echo "WARNING: Using b3_v2 as default PRODUCT NAME"
	PRODUCT_NAME="b3_v2"
fi

case $PRODUCT_NAME in
	"bagheera3")
	    echo "---------------------------------"
	    echo "Applying binaries for Bagheera-3"
	    echo "---------------------------------"
	    ;;
	"b3_v1")
	    echo "---------------------------------"
	    echo "Applying binaries for B3_V1"
	    echo "---------------------------------"
	    ;;
	"b3_v2")
	    echo "---------------------------------"
	    echo "Applying binaries for b3_v2"
	    echo "---------------------------------"
	    ;;
	"octo")
	    echo "---------------------------"
	    echo "Applying binaries for OCTO"
	    echo "---------------------------"
	    ;;
	*)
	    echo "Error: Invalid PRODUCT NAME"
	    ShowUsage "$SCRIPT_NAME"
	    exit 1;
esac

cp -Rfpv $LDK_NV_LOW_LEVEL_BIN_PATH/* $LDK_BOOTLOADER_DIR/

if [ "${DEBUG}" == "true" ]; then
	START_TIME=$(date +%s)
fi

elconfs=("${LDK_BOOTLOADER_DIR}"/extlinux_*)
if [ ${#elconfs[@]} -ge 1 ]; then
        mkdir -p "${LDK_ROOTFS_DIR}/boot/extlinux";
        echo "Installing *extlinux.conf* into /boot in target rootfs"
        for elconf in "${elconfs[@]}"; do
                dest="${LDK_ROOTFS_DIR}"/boot/extlinux/${elconf##*/}
                sudo install --owner=root --group=root --mode=644 -D "${elconf}" "${dest}"
        done
fi

if [ "${TARGET_OVERLAY}" != "true" ] &&
	[ "${USE_TARGET_OVERLAY_DEFAULT}" != "true" ]; then
	if [ ! -f "${LDK_NV_TEGRA_DIR}/${DEB_SCRIPT_NAME}" ]; then
		echo "Debian script ${DEB_SCRIPT_NAME} not found"
		exit 1
	fi
	echo "${LDK_NV_TEGRA_DIR}/${DEB_SCRIPT_NAME}";
	eval "\"${LDK_NV_TEGRA_DIR}/${DEB_SCRIPT_NAME}\" -r \"${LDK_ROOTFS_DIR}\"";
else
	# install standalone debian packages by extracting and dumping them
	# into the rootfs directly for .tbz2 install flow
	pushd "${LDK_TOOLS_DIR}" > /dev/null 2>&1
	debs=($(ls *.deb))
	for deb in "${debs[@]}"; do
		"${DEB_EXTRACTOR}" --dir="${LDK_ROOTFS_DIR}" "${deb}"
	done
	popd > /dev/null 2>&1

	# add gpio as a system group and search unused gid decreasingly from
	# SYS_GID_MAX to SYS_GID_MIN
	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
	AddSystemGroup gpio
	# add crypto and trusty to system group
	AddSystemGroup crypto
	AddSystemGroup trusty
	popd > /dev/null 2>&1

	echo "Extracting the NVIDIA user space components to ${LDK_ROOTFS_DIR}"
	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
	tar -I lbzip2 -xpmf "${LDK_NV_TEGRA_DIR}/nvidia_drivers.tbz2"
	popd > /dev/null 2>&1

	echo "Extracting the BSP test tools to ${LDK_ROOTFS_DIR}"
	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
	tar -I lbzip2 -xpmf "${LDK_NV_TEGRA_DIR}/nv_tools.tbz2"
	popd > /dev/null 2>&1

	echo "Extracting the NVIDIA gst test applications to ${LDK_ROOTFS_DIR}"
	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
	tar -I lbzip2 -xpmf "${LDK_NV_TEGRA_DIR}/nv_sample_apps/nvgstapps.tbz2"
	popd > /dev/null 2>&1

#	echo "Extracting Weston to ${LDK_ROOTFS_DIR}"
#	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
#	tar -I lbzip2 -xpmf "${LDK_NV_TEGRA_DIR}/weston.tbz2"
#	popd > /dev/null 2>&1

	echo "Extracting the configuration files for the supplied root filesystem to ${LDK_ROOTFS_DIR}"
	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
	tar -I lbzip2 -xpmf "${LDK_NV_TEGRA_DIR}/config.tbz2"
	popd > /dev/null 2>&1

#	echo "Extracting graphics_demos to ${LDK_ROOTFS_DIR}"
#	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
#	tar -I lbzip2 -xpmf "${LDK_NV_TEGRA_DIR}/graphics_demos.tbz2"
#	popd > /dev/null 2>&1

	echo "Extracting the firmwares and kernel modules to ${LDK_ROOTFS_DIR}"
	( cd "${LDK_ROOTFS_DIR}" ; tar -I lbzip2 -xpmf "${LDK_KERN_DIR}/kernel_supplements.tbz2" )

	if [ -d "${LDK_ROOTFS_DIR}/lib/modules/4.9.299-tegra/kernel/drivers/net/ethernet/" ]; then
            echo " Deleting ${LDK_ROOTFS_DIR}/lib/modules/4.9.299-tegra/kernel/drivers/net/ethernet/  Contents..."
            rm -rf ${LDK_ROOTFS_DIR}/lib/modules/4.9.299-tegra/kernel/drivers/net/ethernet/*
        fi

        if [ -d "${LDK_ROOTFS_DIR}/lib/modules/4.9.299-tegra/kernel/drivers/net/wireless/" ]; then
            echo " Deleting ${LDK_ROOTFS_DIR}/lib/modules/4.9.299-tegra/kernel/drivers/net/wireless/  Contents..."
            rm -rf ${LDK_ROOTFS_DIR}/lib/modules/4.9.299-tegra/kernel/drivers/net/wireless/*
        fi

	echo "copy kernel headers to ${LDK_ROOTFS_DIR}/usr/src"
	cp ${LDK_KERN_DIR}/kernel_headers.tbz2 ${LDK_ROOTFS_DIR}/usr/src
	# The kernel headers package can be used on the target device as well as on another host.
	# When used on the target, it should go into /usr/src and owned by root.
	# Note that there are multiple linux-headers-* directories; one for use on an
	# x86-64 Linux host and one for use on the L4T target.
	EXTMOD_DIR=ubuntu18.04_aarch64
	KERNEL_HEADERS_A64_DIR="$(tar tf "${LDK_KERN_DIR}/kernel_headers.tbz2" | grep "${EXTMOD_DIR}" | head -1 | cut -d/ -f1)"
	KERNEL_VERSION="$(echo "${KERNEL_HEADERS_A64_DIR}" | sed -e "s/linux-headers-//" -e "s/-${EXTMOD_DIR}//")"
	KERNEL_SUBDIR="kernel-$(echo "${KERNEL_VERSION}" | cut -d. -f1-2)"
	install -o 0 -g 0 -m 0755 -d "${LDK_ROOTFS_DIR}/usr/src"
	pushd "${LDK_ROOTFS_DIR}/usr/src" > /dev/null 2>&1
	# This tar is packaged for the host (all files 666, dirs 777) so that when
	# extracted on the host, the user's umask controls the permissions.
	# However, we're now installing it into the rootfs, and hence need to
	# explicitly set and use the umask to achieve the desired permissions.
	#(umask 022 && tar -xvf "${LDK_KERN_DIR}/kernel_headers.tbz2")
	# Link to the kernel headers from /lib/modules/<version>/build
	KERNEL_MODULES_DIR="${LDK_ROOTFS_DIR}/lib/modules/${KERNEL_VERSION}"
	echo "kernel version directory ${KERNEL_VERSION}"
	if [ -d "${KERNEL_MODULES_DIR}" ]; then
		echo "Adding symlink ${KERNEL_MODULES_DIR}/build --> /usr/src/${KERNEL_HEADERS_A64_DIR}/${KERNEL_SUBDIR}"
		[ -h "${KERNEL_MODULES_DIR}/build" ] && unlink "${KERNEL_MODULES_DIR}/build" && rm -f "${KERNEL_MODULES_DIR}/build"
		[ ! -h "${KERNEL_MODULES_DIR}/build" ] && ln -s "/usr/src/${KERNEL_HEADERS_A64_DIR}/${KERNEL_SUBDIR}" "${KERNEL_MODULES_DIR}/build"
	fi
	popd > /dev/null

	# Copy kernel related files to rootfs
	"${LDK_DIR}/nv_tools/scripts/nv_apply_kernel_files.sh" "${LDK_KERN_DIR}" \
		"${LDK_ROOTFS_DIR}" "--owner=root --group=root";
fi

# Customize rootfs
"${LDK_DIR}/nv_tools/scripts/nv_customize_rootfs.sh" "${LDK_ROOTFS_DIR}"

# Installing INIT script to rootfs
rm -rf ${LDK_DIR}/sources/utils/lib/ntdi_bag3.service
rm -rf ${LDK_DIR}/sources/utils/lib/ntdi_octo.service
rm -rf ${LDK_ROOTFS_DIR}/lib/systemd/system/ntdi_bag3.service
rm -rf ${LDK_ROOTFS_DIR}/lib/systemd/system/ntdi_octo.service
rm -rf ${LDK_ROOTFS_DIR}/etc/init.d/ntdi_bag3_startup
rm -rf ${LDK_ROOTFS_DIR}/etc/init.d/ntdi_octo_startup

mkdir -p ${LDK_ROOTFS_DIR}/bin/vendor/

case $PRODUCT_NAME in
    "bagheera3")
	    cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/usb_cmedia_asoundrc_config ${LDK_ROOTFS_DIR}/root/.asoundrc
            cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/usb_cmedia_asoundrc_config ${LDK_ROOTFS_DIR}/home/ubuntu/.asoundrc
	    cp -Rfpv ${LDK_DIR}/sources/utils/usb_hub/read_ftdi_sn_pn_number.sh ${LDK_ROOTFS_DIR}/bin/vendor/read_ftdi_sn_pn_number.sh
	    chmod 755 ${LDK_ROOTFS_DIR}/bin/vendor/read_ftdi_sn_pn_number.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/usb_hub/99-nd-usb_hub-devices.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/ntdi_bag3.service ${LDK_DIR}/sources/utils/lib/
            cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/80-dms.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
            cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/99-vbus.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/nd_bootconf ${LDK_ROOTFS_DIR}/etc/init.d/.nd_bootconf
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/ntdi_bagheera3_startup ${LDK_ROOTFS_DIR}/etc/init.d/ntdi_bag3_startup
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/sc7_entry_bag3.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_entry.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/sc7_exit_bag3.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_exit.sh
	    #ln -sf /etc/init.d/ntdi_bagheera3_startup ${LDK_ROOTFS_DIR}/etc/init.d/ntdi_bag3_startup
	    #ln -sf /etc/init.d/sc7_entry_bag3.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_entry.sh
	    #ln -sf /etc/init.d/sc7_exit_bag3.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_exit.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/inet_interfaces_config.sh ${LDK_ROOTFS_DIR}/etc/init.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/inet_interfaces_config_up.sh ${LDK_ROOTFS_DIR}/etc/init.d/
	    ln -f sources/image_upgrade/scripts/ov4000_ocam_isp_upgrade_bag3.sh sources/image_upgrade/scripts/ov4000_ocam_isp_upgrade.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/pinmux-cfg/tegra186-mb1-bct-pinmux-p3636-0001-a00-all.cfg ${LDK_BOOTLOADER_DIR}/t186ref/BCT/
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_live_stream.sh ${LDK_ROOTFS_DIR}/bin/vendor/cam_live_stream.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_start.sh ${LDK_ROOTFS_DIR}/bin/vendor/cam_start.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_stop.sh ${LDK_ROOTFS_DIR}/bin/vendor/cam_stop.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_fw_update ${LDK_ROOTFS_DIR}/bin/vendor/cam_fw_update
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_fw_update_orig ${LDK_ROOTFS_DIR}/bin/vendor/cam_fw_update_orig
	    cp -Rfpv ${LDK_DIR}/sources/utils/bin_vendor/change_password ${LDK_ROOTFS_DIR}/bin/vendor/change_password
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/nv-l4t-usb-device-mode-config.sh ${LDK_ROOTFS_DIR}/opt/nvidia/l4t-usb-device-mode/
	    ln -f ${LDK_BOOTLOADER_DIR}/t186ref/BCT/tegra186-mb1-bct-pinmux-p3636-0001-a00-all.cfg ${LDK_BOOTLOADER_DIR}/t186ref/BCT/tegra186-mb1-bct-pinmux-p3636-0001-a00.cfg
	    ;;
    	"b3_v1")
	    cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/usb_cmedia_asoundrc_config ${LDK_ROOTFS_DIR}/root/.asoundrc
            cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/usb_cmedia_asoundrc_config ${LDK_ROOTFS_DIR}/home/ubuntu/.asoundrc
	    cp -Rfpv ${LDK_DIR}/sources/utils/usb_hub/read_ftdi_sn_pn_number.sh ${LDK_ROOTFS_DIR}/bin/vendor/read_ftdi_sn_pn_number.sh
	    chmod 755 ${LDK_ROOTFS_DIR}/bin/vendor/read_ftdi_sn_pn_number.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/usb_hub/99-nd-usb_hub-devices.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/ntdi_bag3.service ${LDK_DIR}/sources/utils/lib/
            cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/80-dms.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
            cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/99-vbus.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/nd_bootconf ${LDK_ROOTFS_DIR}/etc/init.d/.nd_bootconf
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/ntdi_b3_v1_startup ${LDK_ROOTFS_DIR}/etc/init.d/ntdi_bag3_startup
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/sc7_entry_b3_v1.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_entry.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/sc7_exit_b3_v1.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_exit.sh
	    #ln -sf /etc/init.d/ntdi_b3_v1_startup ${LDK_ROOTFS_DIR}/etc/init.d/ntdi_bag3_startup
	    #ln -sf /etc/init.d/sc7_entry_b3_v1.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_entry.sh
	    #ln -sf /etc/init.d/sc7_exit_b3_v1.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_exit.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/inet_interfaces_config.sh ${LDK_ROOTFS_DIR}/etc/init.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/inet_interfaces_config_up.sh ${LDK_ROOTFS_DIR}/etc/init.d/
	    ln -f sources/image_upgrade/scripts/ov4000_ocam_isp_upgrade_b3_v1.sh sources/image_upgrade/scripts/ov4000_ocam_isp_upgrade.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/pinmux-cfg/B3_V1/tegra186-mb1-bct-pinmux-p3636-0001-a00-d450.cfg ${LDK_BOOTLOADER_DIR}/t186ref/BCT/
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_live_stream.sh ${LDK_ROOTFS_DIR}/bin/vendor/cam_live_stream.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_start.sh ${LDK_ROOTFS_DIR}/bin/vendor/cam_start.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_stop.sh ${LDK_ROOTFS_DIR}/bin/vendor/cam_stop.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_fw_update ${LDK_ROOTFS_DIR}/bin/vendor/cam_fw_update
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_fw_update_orig ${LDK_ROOTFS_DIR}/bin/vendor/cam_fw_update_orig
	    cp -Rfpv ${LDK_DIR}/sources/utils/bin_vendor/change_password ${LDK_ROOTFS_DIR}/bin/vendor/change_password
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/nv-l4t-usb-device-mode-config.sh ${LDK_ROOTFS_DIR}/opt/nvidia/l4t-usb-device-mode/
	    ln -f ${LDK_BOOTLOADER_DIR}/t186ref/BCT/tegra186-mb1-bct-pinmux-p3636-0001-a00-d450.cfg ${LDK_BOOTLOADER_DIR}/t186ref/BCT/tegra186-mb1-bct-pinmux-p3636-0001-a00.cfg
	    ;;
	"b3_v2")
	    cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/usb_cmedia_asoundrc_config ${LDK_ROOTFS_DIR}/root/.asoundrc
            cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/usb_cmedia_asoundrc_config ${LDK_ROOTFS_DIR}/home/ubuntu/.asoundrc
	    cp -Rfpv ${LDK_DIR}/sources/utils/usb_hub/read_ftdi_sn_pn_number.sh ${LDK_ROOTFS_DIR}/bin/vendor/read_ftdi_sn_pn_number.sh
	    chmod 755 ${LDK_ROOTFS_DIR}/bin/vendor/read_ftdi_sn_pn_number.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/usb_hub/99-nd-usb_hub-devices.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/80-nd-usb-device.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
	    cp -Rfpv ${LDK_DIR}/build/bin/apps/cmedia_vol_buttons ${LDK_ROOTFS_DIR}/bin/vendor/cmedia_vol_buttons
	    cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/ntdi_usb_device.service ${LDK_ROOTFS_DIR}/lib/systemd/system/ntdi_usb_device.service
	    cp -Rfpv ${LDK_DIR}/sources/utils/bin_vendor/cmedia_usb_vol_btns_ctrl.sh ${LDK_ROOTFS_DIR}/bin/vendor/cmedia_usb_vol_btns_ctrl.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/bin_vendor/cmedia3_setup.sh ${LDK_ROOTFS_DIR}/bin/vendor/cmedia3_setup.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/ntdi_bag3.service ${LDK_DIR}/sources/utils/lib/
	    cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/upgrade_dtb.service ${LDK_DIR}/sources/utils/lib/
            cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/80-dms.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
            cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/99-vbus.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/nd_bootconf ${LDK_ROOTFS_DIR}/etc/init.d/.nd_bootconf
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/ntdi_b3_v2_startup ${LDK_ROOTFS_DIR}/etc/init.d/ntdi_bag3_startup
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/sc7_entry_b3_v2.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_entry.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/sc7_exit_b3_v2.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_exit.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/inet_interfaces_config.sh ${LDK_ROOTFS_DIR}/etc/init.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/inet_interfaces_config_up.sh ${LDK_ROOTFS_DIR}/etc/init.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/upgrade_dtb_old_amp.sh ${LDK_ROOTFS_DIR}/etc/init.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/speaker_retry_count.txt ${LDK_ROOTFS_DIR}/etc/init.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/os_upgrade.sh ${LDK_ROOTFS_DIR}/etc/init.d/
	    #ln -f sources/image_upgrade/scripts/ov491_ocam_isp_upgrade.sh sources/image_upgrade/scripts/ov491_ocam_isp_upgrade.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/pinmux-cfg/B3_V1/tegra186-mb1-bct-pinmux-p3636-0001-a00-d450.cfg ${LDK_BOOTLOADER_DIR}/t186ref/BCT/
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_live_stream_b3_v2.sh ${LDK_ROOTFS_DIR}/bin/vendor/cam_live_stream.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_start_b3_v2.sh ${LDK_ROOTFS_DIR}/bin/vendor/cam_start.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_stop.sh ${LDK_ROOTFS_DIR}/bin/vendor/cam_stop.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_fw_update ${LDK_ROOTFS_DIR}/bin/vendor/cam_fw_update
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_fw_update_orig ${LDK_ROOTFS_DIR}/bin/vendor/cam_fw_update_orig
	    cp -Rfpv ${LDK_DIR}/sources/utils/bin_vendor/change_password ${LDK_ROOTFS_DIR}/bin/vendor/change_password
	    cp -Rfpv ${LDK_DIR}/sources/utils/nvidia/nvargus/libnvscf.so ${LDK_ROOTFS_DIR}/usr/lib/aarch64-linux-gnu/tegra/
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/nv-l4t-usb-device-mode-config.sh ${LDK_ROOTFS_DIR}/opt/nvidia/l4t-usb-device-mode/
	    ln -f ${LDK_BOOTLOADER_DIR}/t186ref/BCT/tegra186-mb1-bct-pinmux-p3636-0001-a00-d450.cfg ${LDK_BOOTLOADER_DIR}/t186ref/BCT/tegra186-mb1-bct-pinmux-p3636-0001-a00.cfg
	    ;;
	"octo")
	    cp -Rfpv ${LDK_DIR}/sources/utils/usb_hub/read_ftdi_sn_pn_number.sh ${LDK_ROOTFS_DIR}/bin/vendor/read_ftdi_sn_pn_number.sh
	    chmod 755 ${LDK_ROOTFS_DIR}/bin/vendor/read_ftdi_sn_pn_number.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/ntdi_octo.service ${LDK_DIR}/sources/utils/lib/
	    cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/nd_bootconf ${LDK_ROOTFS_DIR}/etc/init.d/.nd_bootconf
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/ntdi_octo_startup ${LDK_ROOTFS_DIR}/etc/init.d/
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/sc7_entry_octo.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_entry.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/init.d/sc7_exit_octo.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_exit.sh
	    #ln -sf /etc/init.d/sc7_entry_octo.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_entry.sh
	    #ln -sf /etc/init.d/sc7_exit_octo.sh ${LDK_ROOTFS_DIR}/etc/init.d/sc7_exit.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/usb_hub/99-nd-usb_hub-devices.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
            cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/80-nd-usb-device.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
            cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/80-dms.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
            cp -Rfpv ${LDK_DIR}/sources/utils/bagheera3_init_files/99-vbus.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
            cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/usb_cmedia_asoundrc_config ${LDK_ROOTFS_DIR}/root/.asoundrc
            cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/usb_cmedia_asoundrc_config ${LDK_ROOTFS_DIR}/home/ubuntu/.asoundrc
            mkdir -p ${LDK_ROOTFS_DIR}/bin/vendor/
            cp -Rfpv ${LDK_DIR}/build/bin/apps/cmedia_vol_buttons ${LDK_ROOTFS_DIR}/bin/vendor/cmedia_vol_buttons
            cp -Rfpv ${LDK_DIR}/sources/utils/octo_init_files/ntdi_usb_device.service ${LDK_ROOTFS_DIR}/lib/systemd/system/ntdi_usb_device.service
            cp -Rfpv ${LDK_DIR}/sources/utils/bin_vendor/cmedia_usb_vol_btns_ctrl.sh ${LDK_ROOTFS_DIR}/bin/vendor/cmedia_usb_vol_btns_ctrl.sh
            mkdir -p ${LDK_ROOTFS_DIR}/image_upgrade/
            cp -Rfpv ${LDK_DIR}/build/bin/cmedia_fw_update/fw_update/ ${LDK_ROOTFS_DIR}/image_upgrade/cmedia_usb_audio_fw_update
	    ln -f sources/image_upgrade/scripts/ov4000_ocam_isp_upgrade_bag3.sh sources/image_upgrade/scripts/ov4000_ocam_isp_upgrade.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/pinmux-cfg/tegra186-mb1-bct-pinmux-p3636-0001-a00-all.cfg ${LDK_BOOTLOADER_DIR}/t186ref/BCT/
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_live_stream.sh ${LDK_ROOTFS_DIR}/bin/vendor/cam_live_stream.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_start.sh ${LDK_ROOTFS_DIR}/bin/vendor/cam_start.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_stop.sh ${LDK_ROOTFS_DIR}/bin/vendor/cam_stop.sh
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_fw_update ${LDK_ROOTFS_DIR}/bin/vendor/cam_fw_update
	    cp -Rfpv ${LDK_DIR}/sources/utils/cam_scripts/cam_fw_update_orig ${LDK_ROOTFS_DIR}/bin/vendor/cam_fw_update_orig
	    cp -Rfpv ${LDK_DIR}/sources/utils/bin_vendor/change_password ${LDK_ROOTFS_DIR}/bin/vendor/change_password
	    cp -Rfpv ${LDK_DIR}/sources/utils/etc/nv-l4t-usb-device-mode-config.sh ${LDK_ROOTFS_DIR}/opt/nvidia/l4t-usb-device-mode/
	    ln -f ${LDK_BOOTLOADER_DIR}/t186ref/BCT/tegra186-mb1-bct-pinmux-p3636-0001-a00-all.cfg ${LDK_BOOTLOADER_DIR}/t186ref/BCT/tegra186-mb1-bct-pinmux-p3636-0001-a00.cfg
	    ;;
esac

# Installing INITRD to rootfs
echo "populating initrd to rootfs..."
sudo rm -f "${LDK_BOOTLOADER_DIR}"/initrd; sudo touch "${LDK_BOOTLOADER_DIR}"/initrd;
sudo cp -f "${LDK_BOOTLOADER_DIR}"/initrd "${LDK_ROOTFS_DIR}/boot";

# Installing NTDI_BAG3 Dependent Loadable Modules to rootfs.
sudo mkdir -p rootfs/lib/modules/misc
if [ -d "build/bin/modules" ]; then
        echo "Installing modules into /lib/modules/misc in target rootfs"
        sudo cp build/bin/modules/*.ko rootfs/lib/modules/misc/
	echo "Installing rt v5.9.0.6 version drivers as backup to rootfs"
	sudo cp -r build/bin/modules/rt_bt_wifi_v5.9.0.6 rootfs/lib/modules/misc/
	echo "Installing infineon_wifi modules to rootfs"
	sudo cp -r build/bin/modules/infineon_wifi rootfs/lib/modules/misc/
fi

if [ -d "build/modules/lib/firmware/rtlbt" ]; then
	sudo cp -r build/modules/lib/firmware/rtlbt/ ${LDK_ROOTFS_DIR}/lib/firmware/
fi

# Installing NTDI_BAG3 Dependent Binaries to rootfs.
BIN_PATH="${LDK_ROOTFS_DIR}/bin/vendor"
sudo mkdir -p ${BIN_PATH}
if [ -d "build/bin/stub" ]; then
       chmod 755 -R build/bin/stub
       echo "Installing stub into ${BIN_PATH} in target rootfs"
       sudo cp build/bin/stub/* ${BIN_PATH}
fi
#if [ -d "build/bin/Thirdparty_sdk" ]; then
#       chmod 755 -R build/bin/Thirdparty_sdk
#       echo "Installing Thirdparty_sdk into ${BIN_PATH} in target rootfs"
#       sudo cp build/bin/Thirdparty_sdk/* ${BIN_PATH}
#fi
if [ -d "build/bin/apps" ]; then
       chmod 755 -R build/bin/apps
       echo "Installing apps into ${BIN_PATH} in target rootfs"
       sudo cp build/bin/apps/* ${BIN_PATH}
       cp build/bin/apps/sys_tx2write_x86 ${LDK_BOOTLOADER_DIR}/
       sudo rm -f ${BIN_PATH}/sys_tx2write_x86
fi
if [ -e "build/libsys.so" ]; then
       echo "Installing library into /lib in target rootfs"
       sudo cp build/libsys.so ${LDK_ROOTFS_DIR}/lib
fi

if [ -e "build/bin/thermal_app" ]; then
    chmod 755 -R build/bin/thermal_app
    echo "Installing thermal_app into  target rootfs"
    sudo cp -r build/bin/thermal_app ${LDK_ROOTFS_DIR}
fi

if [ -e "build/bin/pts_app" ]
then
	chmod 755 -R build/bin/pts_app
	echo "Installing pts_app into  target rootfs"
	sudo cp -r build/bin/pts_app ${LDK_ROOTFS_DIR}
else
	echo "NO FILE AVAILBLE -bin !!"
fi

sudo mkdir -p ${LDK_ROOTFS_DIR}/image_upgrade/isp
if [ -f "sources/image_upgrade/scripts/ov4000_incam_isp_upgrade.sh" ]; then
        echo "Copying ISP upgrade script"
        sudo cp sources/image_upgrade/scripts/ov4000_incam_isp_upgrade.sh ${LDK_ROOTFS_DIR}/image_upgrade/isp/.
fi
if [ -f "sources/image_upgrade/scripts/spi0_disable.sh" ]; then
        sudo cp sources/image_upgrade/scripts/spi0_disable.sh ${LDK_ROOTFS_DIR}/image_upgrade/isp/.
fi
if [ -f "sources/image_upgrade/scripts/spi0_enable.sh" ]; then
        sudo cp sources/image_upgrade/scripts/spi0_enable.sh ${LDK_ROOTFS_DIR}/image_upgrade/isp/.
fi
sudo mkdir -p ${LDK_ROOTFS_DIR}/image_upgrade/isp
if [ -f "sources/image_upgrade/scripts/ov4000_ocam_isp_upgrade.sh" ]; then
        echo "Copying ISP upgrade script"
        sudo cp sources/image_upgrade/scripts/ov4000_ocam_isp_upgrade.sh ${LDK_ROOTFS_DIR}/image_upgrade/isp/.
fi
if [ -f "sources/image_upgrade/scripts/ov491_ocam_isp_upgrade.sh" ]; then
        echo "Copying ISP upgrade script"
        sudo cp sources/image_upgrade/scripts/ov491_ocam_isp_upgrade.sh ${LDK_ROOTFS_DIR}/image_upgrade/isp/.
fi
if [ -f "sources/image_upgrade/scripts/spi1_disable.sh" ]; then
        sudo cp sources/image_upgrade/scripts/spi1_disable.sh ${LDK_ROOTFS_DIR}/image_upgrade/isp/.
fi
if [ -f "sources/image_upgrade/scripts/spi1_enable.sh" ]; then
        sudo cp sources/image_upgrade/scripts/spi1_enable.sh ${LDK_ROOTFS_DIR}/image_upgrade/isp/.
fi
sudo mkdir -p ${LDK_ROOTFS_DIR}/image_upgrade/system/
if [ -f "sources/image_upgrade/scripts/rootfs_upgrade.sh" ]; then
        echo "Copying rootfs upgrade script"
        sudo cp sources/image_upgrade/scripts/rootfs_upgrade.sh ${LDK_ROOTFS_DIR}/image_upgrade/system/.
fi

ls sources/image_upgrade/firmware/*.bin
status=$?
if [ $status -eq $success ]; then
	echo "Copying Outcam and Incam Camera Firmwares"
	#chmod 755 sources/image_upgrde/firmware/*.bin
	sudo cp -Rfp sources/image_upgrade/firmware/*.bin ${LDK_ROOTFS_DIR}/image_upgrade/isp/
fi

ls sources/image_upgrade/firmware/cam_backup_fw/*
status=$?
if [ $status -eq $success ]; then
	echo "Copying Previous Camera Firmware"
	sudo cp -r sources/image_upgrade/firmware/cam_backup_fw/ ${LDK_ROOTFS_DIR}/image_upgrade/isp/
fi

sudo mkdir -p ${LDK_ROOTFS_DIR}/image_upgrade/sierra/
if [ -f "sources/image_upgrade/scripts/lte_gps_sierra_upgrade_9x07.sh" ]; then
    echo "Copying LTE upgrade script"
	sudo cp sources/image_upgrade/scripts/lte_gps_sierra_upgrade_9x07.sh ${LDK_ROOTFS_DIR}/image_upgrade/sierra/.
fi

sudo mkdir -p ${LDK_ROOTFS_DIR}/image_upgrade/sierra/firmware
if [ -f "sources/image_upgrade/firmware/9999999_9907152_SWI9X07Y_02.37.03.05_00_GENERIC_002.115_002.spk" ]; then
    echo "Copying LTE Firmware"
    chmod 755 sources/image_upgrade/firmware/9999999_9907152_SWI9X07Y_02.37.03.05_00_GENERIC_002.115_002.spk
	sudo cp sources/image_upgrade/firmware/9999999_9907152_SWI9X07Y_02.37.03.05_00_GENERIC_002.115_002.spk ${LDK_ROOTFS_DIR}/image_upgrade/sierra/firmware/.
fi

sudo mkdir -p ${LDK_ROOTFS_DIR}/image_upgrade/aon
if [ -f "sources/image_upgrade/scripts/aon_image_upgrade.sh" ]; then
    echo "Copying AON Upgrade shell script"
    chmod 755 sources/image_upgrade/scripts/aon_image_upgrade.sh
	sudo cp sources/image_upgrade/scripts/aon_image_upgrade.sh ${LDK_ROOTFS_DIR}/image_upgrade/aon/.
fi

sudo mkdir -p ${LDK_ROOTFS_DIR}/image_upgrade/obd
if [ -f "build/obd-utils/bin/fw_update_mcs" ]; then
	chmod +x build/obd-utils/tools/mcs_reset.sh
	sudo cp -Rfp build/obd-utils/tools/mcs_reset.sh ${LDK_ROOTFS_DIR}/image_upgrade/obd
	sudo cp -Rfp build/obd-utils/tools/fw_bins/* ${LDK_ROOTFS_DIR}/image_upgrade/obd
	chmod +x build/obd-utils/tools/cantest
	sudo cp -Rfp build/obd-utils/tools/cantest ${LDK_ROOTFS_DIR}/image_upgrade/obd
	chmod +x build/obd-utils/bin/fw_update_mcs
	sudo cp -Rfp build/obd-utils/bin/fw_update_mcs ${LDK_ROOTFS_DIR}/image_upgrade/obd
	chmod +x build/obd-utils/bin/start_mcs_app
	sudo cp -Rfp build/obd-utils/bin/start_mcs_app ${LDK_ROOTFS_DIR}/image_upgrade/obd
	chmod +x build/obd-utils/bin/obd_get_feature
	sudo cp -Rfp build/obd-utils/bin/obd_get_feature ${LDK_ROOTFS_DIR}/image_upgrade/obd
fi

if [ -f "sources/image_upgrade/scripts/efm8load.py" ]; then
    echo "Copying AON upgrade python script"
    chmod 755 sources/image_upgrade/scripts/efm8load.py
	sudo cp sources/image_upgrade/scripts/efm8load.py ${LDK_ROOTFS_DIR}/image_upgrade/aon/.
fi

ls sources/image_upgrade/firmware/*.efm8
status=$?
if [ $status -eq $success ]; then
	echo "Copying Aon Application Firmware"
	sudo cp -r sources/image_upgrade/firmware/*.efm8 ${LDK_ROOTFS_DIR}/image_upgrade/aon/
fi

ls sources/image_upgrade/firmware/aon_backup_images/*.efm8
status=$?
if [ $status -eq $success ]; then
	echo "Copying Previous Aon Application Firmware"
	sudo cp -r sources/image_upgrade/firmware/aon_backup_images/ ${LDK_ROOTFS_DIR}/image_upgrade/aon/
fi

sudo mkdir -p ${LDK_ROOTFS_DIR}/image_upgrade/dms
sudo cp -r sources/image_upgrade/firmware/dms_fw/* ${LDK_ROOTFS_DIR}/image_upgrade/dms/

ls sources/image_upgrade/firmware/speaker_fw/*
status=$?
if [ $status -eq $success ]; then
        echo "Copying Speaker Firmware"
        sudo cp -r sources/image_upgrade/firmware/speaker_fw/* ${LDK_ROOTFS_DIR}/lib/firmware/
fi

ls sources/utils/bagheera3_init_files/nvzramconfig.sh
status=$?
if [ $status -eq $success ]; then
        echo "Copying nvzramconfig.sh"
        sudo cp sources/utils/bagheera3_init_files/nvzramconfig.sh ${LDK_ROOTFS_DIR}/etc/systemd/
fi

# USB-UART Binaries
if [ -e "build/usb-uart/prebuilt_libs/" ]; then
       echo "Installing libraries into /usr/lib in target rootfs"
       sudo cp -av build/usb-uart/prebuilt_libs/*.so* ${LDK_ROOTFS_DIR}/usr/lib
fi
if [ -e "build/usb-uart/bin" ]; then
       echo "Installing bins into /usr/bin in target rootfs"
       sudo cp -av build/usb-uart/bin/* ${BIN_PATH}/
fi
if [ -e "$LDK_DIR/build/usb-uart/common/80-nd-ttyACM_obd-device.rules" ]; then
       echo "Installing udev rules into /etc/udev/rules.d/ in target rootfs"
       sudo cp -av $LDK_DIR/build/usb-uart/common/80-nd-ttyACM_obd-device.rules ${LDK_ROOTFS_DIR}/etc/udev/rules.d/
fi

if [ "${DEBUG}" == "true" ]; then
	END_TIME=$(date +%s)
	TOTAL_TIME=$((${END_TIME}-${START_TIME}))
	echo "Time for applying binaries - $(date -d@${TOTAL_TIME} -u +%H:%M:%S)"
fi

echo "Applying binary addition script"
./binary_addition.sh ${LDK_ROOTFS_DIR}
if [ $? -eq 0 ];then
    echo "Binary addition script applied successfully"
else
    echo "Error in applying binary addition script"
fi

if [ -f "version_ntdi.txt" ]; then
echo "Adding the version file"
sudo cp version_ntdi.txt ${LDK_ROOTFS_DIR}/etc/vendor/
fi

echo "Set default user script"
./tools/l4t_create_default_user.sh -u ubuntu -p utnubu --accept-license
if [ $? -eq 0 ];then
    echo "default user script applied successfully"
else
    echo "Error in applying default user script"
fi


echo "Applying rootfs optimization script"
# Disable optiomization for Wifi testing
./rootfs_optimization.sh ${LDK_ROOTFS_DIR}
if [ $? -eq 0 ];then
    echo "Optimization script applied successfully"
else
    echo "Error in applying optimization script"
fi

if [ -f "build/build_details.txt" ];
then
    sudo cp build/build_details.txt ${LDK_ROOTFS_DIR}/etc/vendor/
fi

#Deleting unwanted scripts
echo "Deleting iostat_device_B3.py and root_su.sh"
if [ -e "${LDK_ROOTFS_DIR}/home/ubuntu/.nddevice/CLE_tool/iostat_device_B3.py" ]; then
	rm ${LDK_ROOTFS_DIR}/home/ubuntu/.nddevice/CLE_tool/iostat_device_B3.py
fi
if [ -e "${LDK_ROOTFS_DIR}/home/ubuntu/backup/root_su.sh" ]; then
	rm ${LDK_ROOTFS_DIR}/home/ubuntu/backup/root_su.sh
fi

sudo mkdir -p ${LDK_ROOTFS_DIR}/boot/os_upgrade/
sudo mkdir -p ${LDK_ROOTFS_DIR}/boot/os_upgrade/backup

#Creating the kernel and dtb debians for ota installation
if $UPDATE_DEBS; then
	echo "** Updating the dtb-debian **"
	./kernel/update_dtb.sh
	if [ $? -eq 0 ];then
		echo "dtb-debian created successfully"
	else
		echo "Error in dtb-debian creation"
	fi
	echo "** Updating the kernel-debian **"
	./kernel/update_kernel.sh
	if [ $? -eq 0 ];then
		echo "kernel-deb created successfully"
	else
		echo "Error in kernel-debian creation"
	fi
	ls kernel/kernel-repack/nvidia-l4t-kernel_4.9.299*
	status=$?
	if [ "$status" -eq $success ]; then
		echo "Copying nvidia-l4t-kernel deb file to rootfs"
		sudo cp kernel/kernel-repack/nvidia-l4t-kernel_4.9.299* ${LDK_ROOTFS_DIR}/boot/os_upgrade/nvidia-l4t-kernel_4.9.299_current.deb
	fi
	ls kernel/dtb-repack/nvidia-l4t-kernel-dtbs*
	status=$?
	if [ "$status" -eq $success ]; then
		echo "Copying nvidia-l4t-kernel-dtbs deb file to rootfs"
		sudo cp kernel/dtb-repack/nvidia-l4t-kernel-dtbs_4.9.299* ${LDK_ROOTFS_DIR}/boot/os_upgrade/nvidia-l4t-kernel-dtbs_4.9.299_current.deb
	fi
else
	echo "** Not updating debs --no-debs given **"
fi

./apply_binaries_recovery.sh -p ${PRODUCT_NAME}

echo "Success!"
