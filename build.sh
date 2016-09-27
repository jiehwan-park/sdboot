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
		echo "Usage: ./build.sh [artik10|artik5]"
		exit
	elif [ "$1" = "artik5" ]; then
		uboot_defconfig=artik5_config
		uboot_spl=espresso3250-spl.bin
		kernel_defconfig=artik5_defconfig
		kernel_dtb=exynos3250-artik5.dtb
		output_tar=tizen-sd-boot-artik5.tar.gz
	elif [ "$1" = "artik10" ]; then
		uboot_defconfig=artik10_config
		uboot_spl=smdk5422-spl.bin
		kernel_defconfig=artik10_defconfig
		kernel_dtb=exynos5422-artik10.dtb
		output_tar=tizen-sd-boot-artik10.tar.gz
	else
		exit
	fi
	
	package_check make_ext4fs android-tools-fsutils
	package_check arm-linux-gnueabihf-gcc gcc-arm-linux-gnueabihf

	ARTIK_BUILD_DIR=`pwd`
	OUTPUT_DIR=$ARTIK_BUILD_DIR/output
	TARGET_BOARD=$1
	TARGET_DIR=$OUTPUT_DIR/$TARGET_BOARD
	#BUILD_DATE=`date +"%Y%m%d.%H%M%S"`
	BUILD_DATE=`date +"%Y%m%d"`
	TARGET_DIR=$TARGET_DIR/$BUILD_DATE
	
	BL1="bl1.bin"
	BL2="bl2.bin"
	TZSW="tzsw.bin"

	UBOOT_DIR=$ARTIK_BUILD_DIR/../u-boot-artik
	UBOOT_DEFCONFIG=$uboot_defconfig
	UBOOT_SPL=$uboot_spl
	UBOOT_IMAGE=u-boot.bin
	UBOOT_ENV_SECTION=.rodata
	BOOT_PART_TYPE=vfat

	KERNEL_DIR=$ARTIK_BUILD_DIR/../linux-3.10-artik
	KERNEL_IMAGE=zImage
	KERNEL_DEFCONFIG=$kernel_defconfig
	DTB_PREFIX_DIR=arch/arm/boot/dts/
	BUILD_DTB=$kernel_dtb
	KERNEL_DTB=$kernel_dtb
	PREBUILT_DIR=$ARTIK_BUILD_DIR/prebuilt/$TARGET_BOARD
	RAMDISK_NAME=uInitrd
	MODULE_SIZE=32
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
	cp u-boot $TARGET_DIR
	[ -e u-boot.dtb ] && cp u-boot.dtb $TARGET_DIR
	if [ "$UBOOT_SPL" != "" ]; then
		cp spl/$UBOOT_SPL $TARGET_DIR/$BL2
	fi
	#cp tools/mkimage $TARGET_DIR
}

build_uboot()
{
	pushd $UBOOT_DIR

	make distclean
	make distclean O=$UBOOT_DIR/output
	make $UBOOT_DEFCONFIG O=$UBOOT_DIR/output
	make -j$JOBS O=$UBOOT_DIR/output

	pushd output

	gen_uboot_envs
	install_uboot_output

	popd

	rm -rf output

	popd
}

########## Start build_kernel ##########

build_modules()
{
	mkdir -p $TARGET_DIR/modules
	make modules_install INSTALL_MOD_PATH=$TARGET_DIR/modules INSTALL_MOD_STRIP=1
	make_ext4fs -b 4096 -L modules \
		-l ${MODULE_SIZE}M ${TARGET_DIR}/modules.img \
		${TARGET_DIR}/modules/lib/modules/
	rm -rf ${TARGET_DIR}/modules
}

install_kernel_output()
{
	#cp arch/$ARCH/boot/$KERNEL_IMAGE $TARGET_DIR
	cat arch/$ARCH/boot/$KERNEL_IMAGE $DTB_PREFIX_DIR/$KERNEL_DTB > $TARGET_DIR/$KERNEL_IMAGE
	cp $DTB_PREFIX_DIR/$KERNEL_DTB $TARGET_DIR
	cp vmlinux $TARGET_DIR
}

build_kernel()
{
	pushd $KERNEL_DIR

	make distclean
	make $KERNEL_DEFCONFIG
	make $KERNEL_IMAGE -j$JOBS
	make $BUILD_DTB
	make modules -j$JOBS

	build_modules
	install_kernel_output

	popd
}

########## Start tar_output_images ##########

cp_prebuilt_images()
{
	cp $PREBUILT_DIR/$BL1 $TARGET_DIR/
	cp $PREBUILT_DIR/$TZSW $TARGET_DIR/
	cp $PREBUILT_DIR/$RAMDISK_NAME $TARGET_DIR/
}

tar_output_images()
{
	pushd $TARGET_DIR

	tar -zcvf $ARTIK_BUILD_DIR/$output_tar	\
	$BL1				\
	$BL2				\
	$UBOOT_IMAGE		\
	$TZSW			\
	params.bin			\
	params_recovery.bin	\
	params_sdboot.bin	\
	$KERNEL_IMAGE		\
	$KERNEL_DTB		\
	$RAMDISK_NAME	\
	modules.img

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
