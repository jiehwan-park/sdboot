#!/bin/bash

DEVICE=""
MODEL="artik5"
MODEL_LIST=("artik5" "artik10")
FORMAT=true
RECOVERY=false
PREBUILT_IMAGE=""
PLATFORM_IMAGE=""

BUILD_DIR=`pwd`
TARGET_DIR=""
SDCARD_SIZE=""

BOOTPART=1
MODULESPART=2
ROOTFSPART=3
SYSTEMDATAPART=5
USERPART=6

SDBOOTIMG="sd_boot.img"
BOOTIMG="boot.img"
MODULESIMG="modules.img"
ROOTFSIMG="rootfs.img"
SYSTEMDATAIMG="system-data.img"
USERIMG="user.img"

function setup_env {
	if [ $MODEL = "artik5" ]; then
		KERNEL_DTB="exynos3250-artik5.dtb"
		BOOT_PART_TYPE=vfat
		env_offset=4159
	elif [ $MODEL = "artik10" ]; then
		KERNEL_DTB="exynos5422-artik10.dtb"
		BOOT_PART_TYPE=vfat
		env_offset=4159
	fi

	BL1="bl1.bin"
	BL2="bl2.bin"
	UBOOT="u-boot.bin"
	TZSW="tzsw.bin"
	PARAMS="params.bin"
	INITRD="uInitrd"
	KERNEL="zImage"

	BL1_OFFSET=1
	BL2_OFFSET=31
	UBOOT_OFFSET=63
	TZSW_OFFSET=2111
	ENV_OFFSET=4159

	SKIP_BOOT_SIZE=4
	BOOT_SIZE=32
	MODULE_SIZE=32
	if $RECOVERY; then
		ROOTFS_SIZE=128
	else
		ROOTFS_SIZE=2048
	fi
	DATA_SIZE=1024
	USER_SIZE=""
}

function die {
	if [ -n "$1" ]; then echo $1; fi
	exit 1
}

function contains {
	local n=$#
	local value=${!n}
	for ((i=1;i < $#;i++)) {
		if [ "${!i}" == "${value}" ]; then
			echo "y"
			return 0
		fi
	}
	echo "n"
	return 1
}

function check_options {
	test $(contains "${MODEL_LIST[@]}" $MODEL) == y || die "The model name ($MODEL) is incorrect. Please, enter supported model name.  [artik5|artik10]"

	setup_env

	if [ -z $PREBUILT_IMAGE]; then
		PREBUILT_IMAGE="tizen-sd-boot-"$MODEL".tar.gz"
	fi
	test -e $BUILD_DIR/$PREBUILT_IMAGE  || die "file not found : "$PREBUILT_IMAGE
	test -e $BUILD_DIR/$PLATFORM_IMAGE  || die "file not found : "$PLATFORM_IMAGE

	test "$DEVICE" != "" || die "Please, enter disk name. /dev/sd[x]"
	SIZE=`sudo sfdisk -s $DEVICE`
	test "$SIZE" != "" || die "The disk name ($DEVICE) is incorrect. Please, enter valid disk name.  /dev/sd[x]"

	SDCARD_SIZE=$((SIZE >> 10))
	USER_SIZE=`expr $SDCARD_SIZE - $SKIP_BOOT_SIZE - $BOOT_SIZE - $MODULE_SIZE - $ROOTFS_SIZE - $DATA_SIZE - 2`
	test 100 -lt $USER_SIZE || die  "We recommend to use more than 4GB disk"

	if [ $FORMAT == false ]; then
		test -e $DEVICE$USERPART || die "Need to format the disk. Please, use '-f' option."
	fi
}

function show_usage {
	echo ""
	echo "Usage:"
	echo " ./mk_sdboot.sh [options]"
	echo " ex) ./mk_sdboot.sh -m atrik5 -d /dev/sd[x] -p platform.tar.gz"
	echo " ex) ./mk_sdboot.sh -m atrik5 -d /dev/sd[x] -r"
	echo ""
	echo " Be careful, Just replace the /dev/sd[x] for your device!"
	echo ""
	echo "Options:"
	echo " -h, --help			Show help options"
	echo " -m, --model <name>		Model name ex) -m artik5"
	echo " -d, --disk <name>		Disk name ex) -d /dev/sd[x]"
	#echo " -f, --format				Format & Partition the Disk"
	echo " -r, --recovery			Make a microsd recovery image"
	echo " -b, --prebuilt-image <file>	Prebuilt file name; defulat is tizen-sd-boot-[model].tar.gz"
	echo " -p, --platform-image <file>	Platform file name"
	echo ""
	exit 0
}

function parse_options {
	if [ $# -lt 1 ]; then
		show_usage
		exit 0
	fi

	for opt in  "$@"
	do
		case "$opt" in
			-h|--help)
				show_usage
				shift ;;
			-m|--model)
				MODEL="$2"
				shift ;;
			-d|--disk)
				DEVICE=$2
				shift ;;
			#-f|--format)
			#	FORMAT=true
			#	shift ;;
			-r|--recovery)
				RECOVERY=true
				shift ;;
			-b|--prebuilt-image)
				PREBUILT_IMAGE=$2
				shift ;;
			-p|--platform-image)
				PLATFORM_IMAGE=$2
				shift ;;
			*)
				shift ;;
		esac
	done

	check_options
}

########## Start make_sdbootimg ##########

exynos_sdboot_gen()
{
	local SD_BOOT_SZ=`expr $ENV_OFFSET + 32`

	pushd ${TARGET_DIR}

	dd if=/dev/zero of=$SDBOOTIMG bs=512 count=$SD_BOOT_SZ

	dd conv=notrunc if=$TARGET_DIR/$BL1 of=$SDBOOTIMG bs=512 seek=$BL1_OFFSET
	dd conv=notrunc if=$TARGET_DIR/$BL2 of=$SDBOOTIMG bs=512 seek=$BL2_OFFSET
	dd conv=notrunc if=$TARGET_DIR/$UBOOT of=$SDBOOTIMG bs=512 seek=$UBOOT_OFFSET
	dd conv=notrunc if=$TARGET_DIR/$TZSW of=$SDBOOTIMG bs=512 seek=$TZSW_OFFSET
	dd conv=notrunc if=$TARGET_DIR/$PARAMS of=$SDBOOTIMG bs=512 seek=$ENV_OFFSET

	sync; sync;

	popd
}

make_sdbootimg()
{
	test -e $TARGET_DIR/$BL1 || die "file not found : "$BL1
	test -e $TARGET_DIR/$BL2 || die "file not found : "$BL2
	test -e $TARGET_DIR/$UBOOT || die "file not found : "$UBOOT
	test -e $TARGET_DIR/$TZSW || die "file not found : "$TZSW

	if $RECOVERY; then
		PARAMS="params_recovery.bin"
	else
		PARAMS="params_sdboot.bin"
	fi
	test -e $TARGET_DIR/$PARAMS || die "file not found : "$PARAMS

	exynos_sdboot_gen
}

########## Start make_bootimg ##########

function gen_bootimg {
	dd if=/dev/zero of=$BOOTIMG bs=1M count=$BOOT_SIZE
	if [ "$BOOT_PART_TYPE" == "vfat" ]; then
		mkfs.vfat -n boot $BOOTIMG
	elif [ "$BOOT_PART_TYPE" == "ext4" ]; then
		mkfs.ext4 -F -L boot -b 4096 $BOOTIMG
	fi
}

function install_bootimg {
	test -d mnt || mkdir mnt
	sudo mount -o loop $BOOTIMG mnt

	sudo su -c "install -m 664 $KERNEL mnt"
	sudo su -c "install -m 664 $KERNEL_DTB mnt"
	sudo su -c "install -m 664 $INITRD mnt"

	sync; sync;
	sudo umount mnt

	rm -rf mnt
}

function make_bootimg {
	test -e $TARGET_DIR/$KERNEL || die "file not found : "$KERNEL
	test -e $TARGET_DIR/$KERNEL_DTB || die "file not found : "$KERNEL_DTB
	test -e $TARGET_DIR/$INITRD || die "file not found : "$INITRD

	pushd $TARGET_DIR

	gen_bootimg
	install_bootimg

	popd
}

########## Start make_recoveryimg ##########

function gen_recoveryimg {
	dd if=/dev/zero of=$ROOTFSIMG bs=1M count=$ROOTFS_SIZE
	mkfs.ext4 -F -L rootfs -b 4096 $ROOTFSIMG
}

function install_recoveryimg {
	test -d mnt || mkdir mnt
	sudo mount -o loop $ROOTFSIMG mnt

	sudo su -c "cp $BL1 mnt"
	sudo su -c "cp $BL2 mnt"
	sudo su -c "cp $UBOOT mnt"
	sudo su -c "cp $TZSW mnt"
	sudo su -c "cp $PARAMS mnt"
	sudo su -c "cp $KERNEL mnt"
	sudo su -c "cp $KERNEL_DTB mnt"
	sudo su -c "cp $INITRD mnt"
	sudo su -c "cp $BOOTIMG mnt"
	sudo su -c "cp $MODULESIMG mnt"

	sync; sync;
	sudo umount mnt

	rm -rf mnt
}

function make_recoveryimg {
	PARAMS="params.bin"

	#test -e $TARGET_DIR/$PARAMS || die "file not found : "$PARAMS

	pushd $TARGET_DIR

	gen_recoveryimg
	install_recoveryimg

	popd
}

########## Start fuse_images ##########

function repartition_sd_recovery {
	local BOOT=boot
	local MODULE=modules
	local ROOTFS=rootfs

	echo "========================================"
	echo "Label          dev           size"
	echo "========================================"
	echo $BOOT"		" $DEVICE"1  	" $BOOT_SIZE "MB"
	echo $MODULE"		" $DEVICE"2  	" $MODULE_SIZE "MB"
	echo $ROOTFS"		" $DEVICE"3  	" $ROOTFS_SIZE "MB"

	MOUNT_LIST=`sudo mount | grep $DEVICE | awk '{print $1}'`
	for mnt in $MOUNT_LIST
	do
		sudo umount $mnt
	done

	echo "Remove partition table..."                                                
	sudo su -c "dd if=/dev/zero of=$DEVICE bs=512 count=1 conv=notrunc"

	sudo sfdisk --in-order --Linux --unit M $DEVICE <<-__EOF__
	$SKIP_BOOT_SIZE,$BOOT_SIZE,0xE,*
	,$MODULE_SIZE,,-
	,$ROOTFS_SIZE,,-
	__EOF__

	if [ "$BOOT_PART_TYPE" == "vfat" ]; then
		sudo su -c "mkfs.vfat -F 16 $DEVICE$BOOTPART -n $BOOT"
	elif [ "$BOOT_PART_TYPE" == "ext4" ]; then
		sudo su -c "mkfs.ext4 -q $DEVICE$BOOTPART -L $BOOT -F"
	fi
	sudo su -c "mkfs.ext4 -q $DEVICE$MODULESPART -L $MODULE -F"
	sudo su -c "mkfs.ext4 -q $DEVICE$ROOTFSPART -L $ROOTFS -F"
}

function repartition_sd_boot {
	local BOOT=boot
	local MODULE=modules
	local ROOTFS=rootfs
	local SYSTEMDATA=system-data
	local USER=user

	echo "========================================"
	echo "Label          dev           size"
	echo "========================================"
	echo $BOOT"		" $DEVICE"1  	" $BOOT_SIZE "MB"
	echo $MODULE"		" $DEVICE"2  	" $MODULE_SIZE "MB"
	echo $ROOTFS"		" $DEVICE"3  	" $ROOTFS_SIZE "MB"
	echo "[Extend]""	" $DEVICE"4"
	echo " "$SYSTEMDATA"	" $DEVICE"5  	" $DATA_SIZE "MB"
	echo " "$USER"		" $DEVICE"6  	" $USER_SIZE "MB"

	MOUNT_LIST=`sudo mount | grep $DEVICE | awk '{print $1}'`
	for mnt in $MOUNT_LIST
	do
		sudo umount $mnt
	done

	echo "Remove partition table..."                                                
	sudo su -c "dd if=/dev/zero of=$DEVICE bs=512 count=1 conv=notrunc"

	sudo sfdisk --in-order --Linux --unit M $DEVICE <<-__EOF__
	$SKIP_BOOT_SIZE,$BOOT_SIZE,0xE,*
	,$MODULE_SIZE,,-
	,$ROOTFS_SIZE,,-
	,,E,-
	,$DATA_SIZE,,-
	,$USER_SIZE,,-
	__EOF__

	if [ "$BOOT_PART_TYPE" == "vfat" ]; then
		sudo su -c "mkfs.vfat -F 16 $DEVICE$BOOTPART -n $BOOT"
	elif [ "$BOOT_PART_TYPE" == "ext4" ]; then
		sudo su -c "mkfs.ext4 -q $DEVICE$BOOTPART -L $BOOT -F"
	fi
	sudo su -c "mkfs.ext4 -q $DEVICE$MODULESPART -L $MODULE -F"
	sudo su -c "mkfs.ext4 -q $DEVICE$ROOTFSPART -L $ROOTFS -F"
	sudo su -c "mkfs.ext4 -q $DEVICE$SYSTEMDATAPART -L $SYSTEMDATA -F"
	sudo su -c "mkfs.ext4 -q $DEVICE$USERPART -L $USER -F"
}

function fuse_images {
	if [ -f $TARGET_DIR/$SDBOOTIMG ]; then
		sudo su -c "dd if=$TARGET_DIR/$SDBOOTIMG of=$DEVICE bs=512"
	fi

	if $RECOVERY; then
		repartition_sd_recovery
	else
		repartition_sd_boot
	fi

	if [ -f $TARGET_DIR/$BOOTIMG ]; then
		sudo su -c "dd if=$TARGET_DIR/$BOOTIMG of=$DEVICE$BOOTPART bs=1M"
	fi

	if [ -f $TARGET_DIR/$MODULESIMG ]; then
		sudo su -c "dd if=$TARGET_DIR/$MODULESIMG of=$DEVICE$MODULESPART bs=1M"
	fi
	
	if [ -f $TARGET_DIR/$ROOTFSIMG ]; then
		sudo su -c "dd if=$TARGET_DIR/$ROOTFSIMG of=$DEVICE$ROOTFSPART bs=1M"
	fi

	if [ -f $TARGET_DIR/$SYSTEMDATAIMG ]; then
		sudo su -c "dd if=$TARGET_DIR/$SYSTEMDATAIMG of=$DEVICE$SYSTEMDATAPART bs=1M"
	fi

	if [ -f $TARGET_DIR/$USERIMG ]; then
		sudo su -c "dd if=$TARGET_DIR/$USERIMG of=$DEVICE$USERPART bs=1M"
	fi

	sync; sync;
}

##################################

parse_options "$@"

TARGET_DIR=$BUILD_DIR/$MODEL
test -d $TARGET_DIR || mkdir -p $TARGET_DIR

tar -xvf $PREBUILT_IMAGE -C $TARGET_DIR

make_sdbootimg
make_bootimg
make_recoveryimg

if [ $PLATFORM_IMAGE ]; then
	tar -xvf $PLATFORM_IMAGE -C $TARGET_DIR
fi

fuse_images

rm -rf $TARGET_DIR

