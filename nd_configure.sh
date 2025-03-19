#!/bin/bash

# Copyright (C) 2021 NetraDyne, Inc - All Rights Reserved
# Unauthorized copying of this file, via any medium is strictly prohibited
# Proprietary and confidential
# Written by Ashok Raj<ashok.raj@netradyne.com>, Sep 2021

set -e

function usage()
{
	echo "Usage: ${script_name} [-r <rfs_dir>] [-t <tc_ver>] [-h]"
	echo "  -r, --rootfs       configure rootfs from compressed rootfs file in rfs_dir"
	echo "  -t, --toolchain    configure toolchain of tc_ver version"
	echo "  -a, --all          configure all"
	echo "  -h, --help         print usage"
	exit 1
}

function cleanup()
{
	set +e
	#TODO
}
trap cleanup EXIT


function parse_args()
{
	if [ $# -eq 0 ]; then
	       echo "${script_name}: Default Configuration"
	       rfs_conf=true
	       tc_conf=true
#	       trt_conf=true
	fi

	while [ -n "${1}" ]; do
		case "${1}" in
		-h | --help)
			usage
			;;
		-r | --rootfs)
			[ -n "${2}" ] || ! echo "${script_name}: Not enough parameters" || usage
			rfs_dir="${2}"
			rfs_conf=true
			shift 2
			;;
		-t | --toolchain)
			[ -n "${2}" ] || ! echo "${script_name}: Not enough parameters" || usage
			tc_dir="${2}"
			tc_conf=true
			shift 2
			;;
		-a | --all)
			echo "${script_name}: Configure All"
			rfs_conf=true
			tc_conf=true
			;;
		*)
			echo "Invalid paramenter"
			usage
			exit 1
			;;
		esac
	done
}

function check_pre_req()
{
	this_user="$(whoami)"
	if [ "${this_user}" != "root" ]; then
		echo "${script_name}: Please run as sudo or root user" > /dev/stderr
		usage
		exit 1
	fi

	# Uboot pre-requisites
	apt-get install -y python3-pip bison flex lbzip2 qemu-user-static libxml2-utils
	apt-get install -y awscli --fix-missing
}

function config_rootfs()
{
	echo "Config rootfs"
	local f_name=$(basename $s3_uri_for_rootfs)
	if [[ ! -f $rfs/$f_name && $rfs_conf ]]; then
		#s3cmd sync --recursive s3://netradyne-sharing/bagheera3/sample_rootfs/"${prj_rfs}"/ $rfs/
		#s3cmd sync --recursive s3://netradyne-vvdn-sharing/bagheera3/sample_rootfs/"${prj_rfs}"/ $rfs/
		aws s3 cp --profile s3view $s3_uri_for_rootfs $rfs/
	fi

	if [ ! -f "$l4t_rfs/etc/passwd" ]; then
		# rootfs corrupted, replace it
		echo "rootfs corrupted, replace it"
		cd $l4t_rfs
		shopt -s extglob
		rfs_readme=`rm -vrf !("README.txt")`
		shopt -u extglob
		cd -
		tar xvf "$rfs/$f_name" -C $l4t_rfs
	fi

	# Install Python dependencies
	#pip install pyserial --upgrade -t $l4t_rfs/usr/local/lib/python2.7/dist-packages/
	#pip install pyserial --upgrade -t $l4t_rfs/usr/local/lib/python3.6/dist-packages/
}

function config_recovery_rootfs()
{
	echo "Config recovery_rootfs"
	local f_name=$(basename $s3_uri_for_recovery_rootfs)
	if [[ ! -f $rfs/$f_name && $rfs_conf ]]; then
		#sudo -u $SUDO_USER mkdir -p $rfs
		#s3cmd sync --recursive s3://netradyne-sharing/bagheera3/sample_rootfs/"${prj_rfs}"/ $rfs/
		#s3cmd sync --recursive s3://netradyne-vvdn-sharing/vendor_releases/ntdi_bag2_recovery_rootfs_v1.4.0.4.tar.gz $rfs/
		aws s3 cp --profile s3view $s3_uri_for_recovery_rootfs $rfs/
	fi

	mkdir -vp "$l4t_rrfs"

	if [ ! -f "$l4t_rrfs/etc/passwd" ]; then
		# recovery rootfs corrupted, replace it
		echo "recovery_rootfs corrupted, replace it"
		rm -fr $l4t_rrfs/*
		#cd $l4t_rfs
		#shopt -s extglob
		#rfs_readme=`rm -vrf !("README.txt")`
		#shopt -u extglob
		#cd -
		tar -xvf "$rfs/$f_name" -C $l4t_rrfs
	fi

	# Install Python dependencies
	#pip install pyserial --upgrade -t $l4t_rfs/usr/local/lib/python2.7/dist-packages/
	#pip install pyserial --upgrade -t $l4t_rfs/usr/local/lib/python3.6/dist-packages/
}

function config_toolchain()
{
	echo "Config toolchain"
	if [ ! -d "$linaro_dir" ]; then
		mkdir -p $linaro_dir
	fi

	local f_name=$(basename $s3_uri_for_toolchain)
	if [[ ! -d "$tc_dir" && $tc_conf ]]; then
		if [ ! -f "$linaro_dir/$linaro_tc" ]; then
			#sudo wget "http://releases.linaro.org/components/toolchain/binaries/7.3-2018.05/aarch64-linux-gnu/${linaro_tc}" -P $linaro_dir
			#sudo s3cmd sync --recursive s3://netradyne-sharing/bagheera3/toolchain/${linaro_tc_dir} -P $linaro_dir
			#sudo s3cmd sync --recursive s3://netradyne-vvdn-sharing/bagheera3/toolchain/"${linaro_tc_dir}"/ -P $linaro_dir/
			if [ ! -e $linaro_dir/$f_name ];then
				aws s3 cp "$s3_uri_for_toolchain" $linaro_dir/
			fi
		fi

		tar xvf  "$linaro_dir/$linaro_tc" -C $linaro_dir
	fi
}

<<config_trt
function config_trt()
{
	echo "Config trt"
#	cd ${l4t_dir}

	if [ ! -d "$trt_dir" ]; then
		mkdir -p $trt_dir
	fi
	aws s3 cp "$s3_uri_for_trt" $trt_dir/
	cd $trt_dir
	tar xvf $trt
}
config_trt

rfs_conf=false
tc_conf=false
trt_conf=false
script_name="$(basename "${0}")"
l4t_dir="$(cd "$(dirname "${0}")" && pwd)"
l4t_rfs="${l4t_dir}/rootfs/"
l4t_rrfs="${l4t_dir}/recovery_rootfs/"
prj_dir="${l4t_dir%/*}"
prj="$(basename "${prj_dir}")"
prj_rfs="${prj}_rootfs"
rfs="${prj_dir}_rootfs"
trt_dir="analytics_deb"
trt="821_trt.tar.gz"

#Defaults
rfs_dir="${l4t_dir}/rootfs/"
mkdir -p /opt/linaro/
tc_dir="/opt/linaro/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu"
linaro_dir="$(cd "$(dirname "$tc_dir")" && pwd)"
linaro_tc="gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu.tar.xz"
linaro_tc_dir="gcc-linaro-7.3.1"

#s3_uri_for_rootfs="s3://netradyne-sharing/bagheera3/sample_rootfs/b3_os_v32.6.1_rootfs/tegra_linux_sample-root-filesystem_r32.6.1_aarch64.tbz2"
#s3_uri_for_rootfs="s3://netradyne-sharing/bagheera3/rootfs/b3_os_32.7.2/ndos_primary_rfs_v1_14102022_1454.tar.gz"
#s3_uri_for_rootfs="s3://netradyne-sharing/bagheera3/rootfs/nd_l4t_32.7.3/ndos_primary_rfs_v2_26072023_0557.tar.gz"
#s3_uri_for_rootfs="s3://netradyne-sharing/bagheera3/rootfs/nd_l4t_32.7.3/ndos_primary_rfs_v3_01092023_1455.tar.gz"
#s3_uri_for_rootfs="s3://netradyne-sharing/bagheera3/rootfs/nd_l4t_32.7.3/ndos_primary_rfs_v5_03102023_1320.tar.gz"
#s3_uri_for_rootfs="s3://netradyne-sharing/bagheera3/rootfs/nd_l4t_32.7.3/ndos_primary_rfs_v6_05102023_1715.tar.gz"
s3_uri_for_rootfs="s3://netradyne-sharing/bagheera3/rootfs/nd_l4t_32.7.3/ndos_primary_rfs_v7_10072024_1416.tar.gz"
s3_uri_for_recovery_rootfs="s3://netradyne-sharing/bagheera3/rootfs/nd_l4t_32.7.3/ndos_recovery_rfs_v1_03052023_1937.tar.gz"
#s3_uri_for_recovery_rootfs="s3://netradyne-sharing/bagheera3/sample_rootfs/b3_os_v32.6.1_rootfs/nd_recovery_rootfs_v1.tar.gz"
s3_uri_for_toolchain="s3://netradyne-vvdn-sharing/bagheera3/toolchain/gcc-linaro-7.3.1/gcc-linaro-7.3.1-2018.05-x86_64_aarch64-linux-gnu.tar.xz"
s3_uri_for_trt="s3://netradyne-sharing/bagheera3/TRT_8.2.1_v2/821_trt.tar.gz"

parse_args "${@}"
check_pre_req
mkdir -p $rfs
config_rootfs
config_recovery_rootfs
config_toolchain

# TRT installed in rootfs, hence config_trt is disabled
#config_trt

#cd ${l4t_dir}
#./trt.sh
