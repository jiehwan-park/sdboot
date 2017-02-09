#!/bin/bash

export ARCH=arm
export JOBS=`getconf _NPROCESSORS_ONLN`
export CROSS_COMPILE=arm-linux-gnueabihf-

set -e

error()
{
	JOB="$0"              # job name
	LASTLINE="$1"         # line of error occurrence
	LASTERR="$2"          # error code
	echo "ERROR in ${JOB} : line ${LASTLINE} with exit code ${LASTERR}"
	exit 1
}

package_check()
{
	command -v $1 >/dev/null 2>&1 || { echo >&2 "${1} not installed. Please install \"sudo apt-get install $2\""; exit 1; }
}

set_envs()
{
	if [ $# -lt 1 ]; then
		echo "Usage: ./build.sh [artik10|artik5|artik530|artik710]"
		exit
	elif [ "$1" = "artik5" ]; then
		chip_name=espresso3250
		uboot_defconfig=artik5_config
		uboot_spl=espresso3250-spl.bin
		uboot_image=u-boot.bin
		uboot_dir=u-boot-artik
		uboot_env_section=.rodata
		kernel_defconfig=artik5_defconfig
		kernel_dtb=exynos3250-artik5.dtb
		kernel_dir=linux-3.10-artik
		kernel_image=zImage
	elif [ "$1" = "artik10" ]; then
		chip_name=smdk5422
		uboot_defconfig=artik10_config
		uboot_spl=smdk5422-spl.bin
		uboot_image=u-boot.bin
		uboot_dir=u-boot-artik
		uboot_env_section=.rodata
		kernel_defconfig=artik10_defconfig
		kernel_dtb=exynos5422-artik10.dtb
		kernel_dir=linux-3.10-artik
		kernel_image=zImage
	elif [ "$1" = "artik530" ]; then
		chip_name=s5p4418
		uboot_defconfig=artik530_raptor_config
		uboot_spl=
		uboot_image=bootloader.img
		uboot_dir=u-boot-artik7
		uboot_env_section=.rodata.default_environment
		kernel_defconfig=artik530_raptor_defconfig
		kernel_dtb=s5p4418-artik530-raptor-*.dtb
		kernel_dir=linux-artik7
		kernel_image=zImage
	elif [ "$1" = "artik710" ]; then
		export ARCH=arm64
		export CROSS_COMPILE=aarch64-linux-gnu-

		chip_name=s5p6818
		uboot_defconfig=artik710_raptor_config
		uboot_spl=
		uboot_image=fip-nonsecure.img
		uboot_dir=u-boot-artik7
		uboot_env_section=.rodata.default_environment
		kernel_defconfig=artik710_raptor_defconfig
		kernel_dtb=s5p6818-artik710-raptor-*.dtb
		kernel_dir=linux-artik7
		kernel_image=Image
		dtb_suffix=/nexell
	else
		exit
	fi
	
	package_check make_ext4fs android-tools-fsutils
	package_check arm-linux-gnueabihf-gcc gcc-arm-linux-gnueabihf

	ARTIK_BUILD_DIR=`pwd`
	CHIP_NAME=$chip_name
	OUTPUT_DIR=$ARTIK_BUILD_DIR/output
	TARGET_BOARD=$1
	TARGET_DIR=$OUTPUT_DIR/$TARGET_BOARD
	#BUILD_DATE=`date +"%Y%m%d.%H%M%S"`
	BUILD_DATE=`date +"%Y%m%d"`
	TARGET_DIR=$TARGET_DIR/$BUILD_DATE
	
	#BL1="bl1.bin"
	#BL2="bl2.bin"
	#TZSW="tzsw.bin"

	UBOOT_DIR=$ARTIK_BUILD_DIR/../$uboot_dir
	UBOOT_DEFCONFIG=$uboot_defconfig
	UBOOT_SPL=$uboot_spl
	UBOOT_IMAGE=$uboot_image
	UBOOT_ENV_SECTION=$uboot_env_section
	BOOT_PART_TYPE=vfat

	KERNEL_DIR=$ARTIK_BUILD_DIR/../$kernel_dir
	KERNEL_IMAGE=$kernel_image
	KERNEL_DEFCONFIG=$kernel_defconfig
	DTB_PREFIX_DIR=arch/${ARCH}/boot/dts${dtb_suffix}
	KERNEL_DTB=$kernel_dtb
	PREBUILT_DIR=$ARTIK_BUILD_DIR/prebuilt/$TARGET_BOARD
	RAMDISK_NAME=uInitrd
	MODULE_SIZE=32

	OUTPUT_TAR=tizen-sd-boot-${TARGET_BOARD}.tar.gz
}

die() {
	if [ -n "$1" ]; then echo $1; fi
	exit 1
}

########## Start build_uboot ##########

gen_uboot_envs()
{
	cp `find . -name "env_common.o"` copy_env_common.o
	${CROSS_COMPILE}objcopy -O binary --only-section=$UBOOT_ENV_SECTION \
		`find . -name "copy_env_common.o"`

	tr '\0' '\n' < copy_env_common.o | grep '=' > default_envs.txt
	cp default_envs.txt default_envs.txt.orig
	tools/mkenvimage -s 16384 -o params.bin default_envs.txt

	# Generate recovery param
	sed -i -e 's/rootdev=.*/rootdev=1/g' default_envs.txt
	sed -i -e 's/partitions=uuid_disk/partitions_default=uuid_disk/g' default_envs.txt
	sed -i -e 's/partitions_tizen=uuid_disk/partitions=uuid_disk/g' default_envs.txt
	sed -i -e 's/bootcmd=run .*/bootcmd=run sdrecovery/g' default_envs.txt
	tools/mkenvimage -s 16384 -o params_recovery.bin default_envs.txt

	# Generate sd-boot param
	cp default_envs.txt.orig default_envs.txt
	sed -i -e 's/rootdev=.*/rootdev=1/g' default_envs.txt
	tools/mkenvimage -s 16384 -o params_sdboot.bin default_envs.txt
}

install_uboot_output()
{
	cp $UBOOT_IMAGE $TARGET_DIR
	chmod 664 params.bin params_*.bin
	cp params.bin params_* $TARGET_DIR
	#cp u-boot $TARGET_DIR
	#[ -e u-boot.dtb ] && cp u-boot.dtb $TARGET_DIR
	if [ "$UBOOT_SPL" != "" ]; then
		cp spl/$UBOOT_SPL $TARGET_DIR/bl2.bin
	fi
	#cp tools/mkimage $TARGET_DIR
}

gen_fip_image()
{
	if [ "$UBOOT_IMAGE" = "fip-nonsecure.img" ]; then
		$UBOOT_DIR/output/tools/fip_create/fip_create --dump --bl33 u-boot.bin fip-nonsecure.bin
	fi
}

gen_nexell_image()
{
	local chip_name=$(echo -n ${CHIP_NAME} | awk '{print toupper($0)}')
	case "$CHIP_NAME" in
		s5p4418)
			nsih_name=raptor-emmc.txt
			input_file=u-boot.bin
			output_file=$UBOOT_IMAGE
			gen_tool=BOOT_BINGEN
			FIP_LOAD_ADDR=0x43c00000
			launch_addr=$FIP_LOAD_ADDR
			;;
		s5p6818)
			nsih_name=raptor-64.txt
			input_file=fip-nonsecure.bin
			output_file=fip-nonsecure.img
			hash_file=fip-nonsecure.bin.hash
			gen_tool=SECURE_BINGEN
			FIP_LOAD_ADDR=0x7df00000
			launch_addr=0x00000000
			;;
		*)
			return 0 ;;
	esac

	tools/nexell/${gen_tool} \
		-c $UBOOT_DIR/output/$chip_name -t 3rdboot \
		-n $UBOOT_DIR/tools/nexell/nsih/${nsih_name} \
		-i $UBOOT_DIR/output/${input_file} \
		-o $UBOOT_DIR/output/${output_file} \
		-l $FIP_LOAD_ADDR -e ${launch_addr}
}

build_uboot()
{
	pushd $UBOOT_DIR

	make distclean
	make distclean O=$UBOOT_DIR/output
	make $UBOOT_DEFCONFIG O=$UBOOT_DIR/output
	make -j$JOBS O=$UBOOT_DIR/output

	pushd output

	gen_fip_image
	gen_nexell_image
	gen_uboot_envs
	install_uboot_output

	popd

	rm -rf output

	popd
}

########## Start build_kernel ##########

build_modules()
{
	make modules_prepare
	make modules -j$JOBS

	mkdir -p $TARGET_DIR/modules
	make modules_install INSTALL_MOD_PATH=$TARGET_DIR/modules INSTALL_MOD_STRIP=1
	make_ext4fs -b 4096 -L modules \
		-l ${MODULE_SIZE}M ${TARGET_DIR}/modules.img \
		${TARGET_DIR}/modules/lib/modules/
	rm -rf ${TARGET_DIR}/modules
}

install_kernel_output()
{
	if [ $TARGET_BOARD = "artik5" ] || [ $TARGET_BOARD = "artik10" ]; then
		cat arch/$ARCH/boot/$KERNEL_IMAGE $DTB_PREFIX_DIR/$KERNEL_DTB > $TARGET_DIR/$KERNEL_IMAGE
	else
		cp arch/$ARCH/boot/$KERNEL_IMAGE $TARGET_DIR
	fi
	cp $DTB_PREFIX_DIR/$KERNEL_DTB $TARGET_DIR
}

build_kernel()
{
	pushd $KERNEL_DIR

	make distclean
	make $KERNEL_DEFCONFIG
	make $KERNEL_IMAGE -j$JOBS
	make dtbs

	build_modules
	install_kernel_output

	popd
}

########## Start tar_output_images ##########

cp_prebuilt_images()
{
	cp $PREBUILT_DIR/* $TARGET_DIR/
}

tar_output_images()
{
	pushd $TARGET_DIR

	tar -zcvf $ARTIK_BUILD_DIR/$OUTPUT_TAR *

	popd
}

#######################################

trap 'error ${LINENO} ${?}' ERR

set_envs $@

test -d $TARGET_DIR || mkdir -p $TARGET_DIR

build_uboot
build_kernel
cp_prebuilt_images
tar_output_images
