#!/bin/bash

script_name=$0
script_name=`realpath $0`
PRODUCT_NAME=$1
options=$2

usage()
{
	echo "Usage:"
	echo "$script_name <Product Names> <'optional aurguments'>"
	echo "Supported Product Names are:"
	echo "    - bagheera3"
	echo "    - b3_v1"
	echo "    - b3_v2"
	echo "    - octo"
	echo ""
	echo "optional aurguments: Should provide flash.sh suppoerted arguments"
	echo "NOTE: options must be enclosed in single quote ('options')"
	echo ""
	echo ""
	echo "e.g. for Bagheera3 flashing:"
	echo "    $script_name bagheera3 '--no-flash ROOTFS_AB=1'"
	echo ""
	echo ""
}

if [ -z $PRODUCT_NAME ];then
	echo "Error: Invalid PRODUCT NAME"
	usage
	exit 1
fi

target_name=""
block_device="mmcblk0p1"
case $PRODUCT_NAME in
	"bagheera3")
	    target_name="jetson-tegra186-nd-bagheera3"
	    block_device="mmcblk0p1"
	    ;;
	"b3_v1")
	    target_name="jetson-tegra186-nd-b3_v1"
	    block_device="mmcblk0p1"
	    ;;
	"b3_v2")
	    target_name="jetson-tegra186-nd-b3_v2"
	    block_device="mmcblk0p1"
	    ;;
	"octo")
	    target_name="jetson-tegra186-nd-octo"
	    block_device="mmcblk0p1"
	    ;;
	*)
	    echo "Error: Invalid PRODUCT NAME"
	    usage
	    exit 1;
esac

dir_name=`dirname $script_name`
flash_tool=$dir_name/flash.sh

echo "flashing Command: $flash_tool $options $target_name $block_device"

$flash_tool $options $target_name $block_device

