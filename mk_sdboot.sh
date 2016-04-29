#!/bin/bash

DEVICE=""
MODEL="artik5"
FORMAT=""
WRITE=""
TARNAME=""
FILENAME=""
FOLDERNAME=""
FOLDERTMP="tizen_boot"

BL1="bl1.bin"
BL2="bl2.bin"
UBOOT="u-boot.bin"
TZSW="tzsw.bin"
PARAMS="params.bin"
INITRD="uInitrd"
KERNEL="zImage"
DTBARTIK5="exynos3250-artik5.dtb"
DTBARTIK10="exynos5422-artik10.dtb"
MODULESIMG="modules.img"
ROOTFSIMG="rootfs.img"
SYSTEMDATAIMG="system-data.img"
USERIMG="user.img"

MODULESPART=2
ROOTFSPART=3
SYSTEMDATAPART=5
USERPART=6

BL1_OFFSET=1
BL2_OFFSET=31
UBOOT_OFFSET=63
TZSW_OFFSET=719
PARAMS_OFFSET=1031

function show_usage {
	echo "Usage:"
	echo " sudo ./mk_sdboot.sh -f /dev/sd[x]"
	echo " sudo ./mk_sdboot.sh -w /dev/sd[x] <file name>"
	echo ""
	echo " Be careful, Just replace the /dev/sd[x] for your device!"
}

function partition_format {
	DISK=$DEVICE
	SIZE=`sfdisk -s $DISK`
	SIZE_MB=$((SIZE >> 10))

	BOOT_SZ=32
	MODULE_SZ=32
	ROOTFS_SZ=2048
	DATA_SZ=256

	echo $SIZE_MB
	let "USER_SZ = $SIZE_MB - $BOOT_SZ - $ROOTFS_SZ - $DATA_SZ - $MODULE_SZ - 4"

	BOOT=boot
	ROOTFS=rootfs
	SYSTEMDATA=system-data
	USER=user
	MODULE=modules

	if [[ $USER_SZ -le 100 ]]
	then
		echo "We recommend to use more than 4GB disk"
		exit 0
	fi

	echo "========================================"
	echo "Label          dev           size"
	echo "========================================"
	echo $BOOT"		" $DISK"1  	" $BOOT_SZ "MB"
	echo $MODULE"		" $DISK"2  	" $MODULE_SZ "MB"
	echo $ROOTFS"		" $DISK"3  	" $ROOTFS_SZ "MB"
	echo "[Extend]""	" $DISK"4"
	echo " "$SYSTEMDATA"	" $DISK"5  	" $DATA_SZ "MB"
	echo " "$USER"		" $DISK"6  	" $USER_SZ "MB"

	MOUNT_LIST=`mount | grep $DISK | awk '{print $1}'`
	for mnt in $MOUNT_LIST
	do
		umount $mnt
	done

	echo "Remove partition table..."                                                
	dd if=/dev/zero of=$DISK bs=512 count=1 conv=notrunc

	sfdisk --in-order --Linux --unit M $DISK <<-__EOF__
	4,$BOOT_SZ,0xE,*
	,$MODULE_SZ,,-
	,$ROOTFS_SZ,,-
	,,E,-
	,$DATA_SZ,,-
	,$USER_SZ,,-
	__EOF__

	mkfs.vfat -F 16 ${DISK}1 -n $BOOT
	mkfs.ext4 -q ${DISK}2 -L $MODULE -F
	mkfs.ext4 -q ${DISK}3 -L $ROOTFS -F
	mkfs.ext4 -q ${DISK}5 -L $SYSTEMDATA -F
	mkfs.ext4 -q ${DISK}6 -L $USER -F
}

function find_model {
	TMPNAME=${TARNAME/artik10/found}
	if [ $TARNAME != $TMPNAME ]; then
		MODEL="artik10"
		PARAMS_OFFSET=1031
	fi
}

function write_image {
	echo "writing $FILENAME ..."
	if [ $FILENAME == $BL1 ]; then
		dd if=$FOLDERNAME"/"$BL1 of=$DEVICE bs=512 seek=$BL1_OFFSET conv=notrunc
		return
	fi
	if [ $FILENAME == $BL2 ]; then
		dd if=$FOLDERNAME"/"$BL2 of=$DEVICE bs=512 seek=$BL2_OFFSET conv=notrunc
		return
	fi
	if [ $FILENAME == $UBOOT ]; then
		dd if=$FOLDERNAME"/"$UBOOT of=$DEVICE bs=512 seek=$UBOOT_OFFSET conv=notrunc
		return
	fi
	if [ $FILENAME == $TZSW ]; then
		dd if=$FOLDERNAME"/"$TZSW of=$DEVICE bs=512 seek=$TZSW_OFFSET conv=notrunc
		return
	fi
	if [ $FILENAME == $PARAMS ]; then
		dd if=$FOLDERNAME"/"$PARAMS of=$DEVICE bs=512 seek=$PARAMS_OFFSET conv=notrunc
		return
	fi

	if [ $FILENAME == $INITRD ] || [ $FILENAME == $KERNEL ] || [ $FILENAME == $DTBARTIK5 ] || [ $FILENAME == $DTBARTIK10 ]; then
		mkdir $FOLDERTMP
		mount ${DEVICE}1 $FOLDERTMP
		cp $FOLDERNAME"/"$FILENAME $FOLDERTMP
		sync
		umount $FOLDERTMP
		rm -rf $FOLDERTMP
		sync
		return
	fi

	if [ $FILENAME == $MODULESIMG ]; then
		dd if=$FOLDERNAME"/"$FILENAME of=${DEVICE}${MODULESPART} bs=1M
		return
	fi

	if [ $FILENAME == $ROOTFSIMG ]; then
		dd if=$FOLDERNAME"/"$FILENAME of=${DEVICE}${ROOTFSPART} bs=1M
		return
	fi

	if [ $FILENAME == $SYSTEMDATAIMG ]; then
		dd if=$FOLDERNAME"/"$FILENAME of=${DEVICE}${SYSTEMDATAPART} bs=1M
		return
	fi

	if [ $FILENAME == $USERIMG ]; then
		dd if=$FOLDERNAME"/"$FILENAME of=${DEVICE}${USERPART} bs=1M
		return
	fi
}

function write_images {
	FOLDERNAME=${TARNAME%%.*}
	find_model

	mkdir $FOLDERNAME
	for FILENAME in `tar xvf $TARNAME -C $FOLDERNAME`
	do
		write_image
		sync
	done
	rm -rf $FOLDERNAME
}

function cmd_run {
	if [ "$DEVICE" == "/dev/sdX" ]; then
		echo "Just replace the /dev/sdX for your device!"
		show_usage
		exit 0
	fi
	
	if [ "$WRITE" == "1" ]; then
		if [ "$DEVICE" == "" ] || [ "$TARNAME" == "" ]; then
			show_usage
			exit 0
		fi
	
		echo " === Start writing $TARNAME images === "
		write_images
		echo " === end writing $TARNAME images === "
	fi

	if [ "$FORMAT" == "1" ]; then
		if [ "$DEVICE" == "" ]; then
			show_usage
			exit 0
		fi
		
		echo " === Start $DEVICE format === "
		partition_format
		echo " === end $DEVICE format === "
	fi
}

function check_args {
	if [ "$WRITE" == "" ] && [ "$FORMAT" == "" ]; then
		show_usage
		exit 0
	fi
}

while test $# -ne 0; do
	option=$1
	shift

	case $option in
		-f|--format)
			FORMAT="1"
			DEVICE=$1
			shift
			;;
		-w|--write)
			WRITE="1"
			DEVICE=$1
			shift
			TARNAME=$1
			shift
			;;
		*)
			;;
	esac
done

check_args
cmd_run

