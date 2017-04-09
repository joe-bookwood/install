#!/bin/sh
#
# Gentoo automated install build script 
#
# NOTE: this script is under CVS control

#
# Globals
#
HDA_MEDIA=""
SDA_MEDIA=""
IDE=0
SCSI=0
DISK=""
MEM=""
SWAP=""
BPS=""
BPB=""
DISK_BLOCKS=""
DISK_SIZE=""
OUT=""
FS_CMD=""
UINPUT=""
WORK=1
RE_REQ=""
ERR_FILE="install_error.txt"

SERVER_IP=`ip route | grep default | egrep -o '([0-9]{1,3}\.){3}[0-9]+' | uniq`
# Constants
BASE_GENTOO_VERSION="1.4"
GIG=1073741824
MEG=1048576
STAGE_ONE="/mnt/cdrom/stage1-x86-2008.0.tar.bz2"
#STAGE_ONE="/mnt/cdrom/stage1-x86-2007.1.tar.bz2"
ARCH=`uname -m`
if [ "`uname -m`" = "x86_64" ]
then
STAGE_THREE="/mnt/cdrom/stage3-amd64-*.tar.bz2"
else
STAGE_THREE="/mnt/cdrom/stage3-i686-*.tar.bz2"
fi
PORTAGE_SNAPSHOT="/mnt/cdrom/portage-latest.tar.xz"
#REM_FS="binaryserver.yourdomain.com:/gentoo/dist/${BASE_GENTOO_VERSION}"
REM_FS="$SERVER_IP:/install/gentoo/"
SETUP_FILES="/mnt/cdrom/setup_files"
DHCP_INFO="/var/lib/dhcpc/dhcpcd-eth0.info"

# Partition sizes
MAX_SWAP=$((4*$GIG))
MIN_SWAP=$(($GIG/2))
BOOT_SIZE=$((50*$MEG))
ROOT_SIZE=$((10*$GIG))
MIN_RE=$((2*$GIG)) 		# minimum sized research partition

# File system types
BOOT_FS="ext2"
ROOT_FS="xfs"
RE_FS="xfs"
RE_FLAG=0

# Source the Gentoo functions script
#source /mnt/cdrom/source-amd64/sbin/functions.sh
source /etc/init.d/functions.sh


# set time
ntpdate ptbtime1.ptb.de
#
# Local Functions
#

# Collects user input if existing linux or NTFS partitions are found before
# initial disk repartitioning.

function muyfm() {
	UINPUT=""
    echo -n -e "\a"
    echo -e "\n\t[E]xit install\n\t[C]ontinue install repartition disk  (default)\n\n"
    einfon "Repartioning disk in 30 seconds, select alternate option now"
    read -t 30 -p " [E|C]: " UINPUT
    if [ x"$UINPUT" == x"e" ] || [ x"$UINPUT" == x"E" ]; then
        einfo "Install cancelled at users request"
        exit
    elif [ x"$UINPUT" == x"c" ] || [ x"$UINPUT" == x"C" ]; then
        einfo "User requests disk repartition"
        return 0
    elif [ x"$UINPUT" != x"" ]; then
        eerror "Unknown command"
        muyfm
    elif [ $? != 0 ]; then
		echo -e "\n"
        einfo "No user input, default install continuing, repartioning disk"
        return 0
    fi
}

# Prompt user to see if this is a work or home install

function do_post() {
	UINPUT=""
    echo -e "\a"
	ewarn "Please decide what kind of install you wish to perform"
	echo -e "[L]VM install (default)\n\t[W]ork install\n\t[H]ome install (postinstall not run)\n\n"
    einfon "Defaulting to work install in 30 seconds "
    read -t 30 -p " [L|W|H]: " UINPUT
    if [ x"$UINPUT" == x"w" ] || [ x"$UINPUT" == x"W" ]; then
        einfo "Work install selected, postinstall will run"
		WORK=1
        return 0
    elif [ x"$UINPUT" == x"l" ] || [ x"$UINPUT" == x"L" ]; then
        einfo "Home install selected, postinstall will not run"
		WORK=2
        return 0
    elif [ x"$UINPUT" == x"h" ] || [ x"$UINPUT" == x"H" ]; then
        einfo "Home install selected, postinstall will not run"
		WORK=0
        return 0
    elif [ x"$UINPUT" != x"" ]; then
        eerror "Unknown command"
        muyfm
    elif [ $? != 0 ]; then
		echo -e "\n"
        einfo "No user input, defaulting to work install" 
		WORK=2
        return 0
    fi
}

# Home install, user supplied disk partitions

function do_home_part() {
	UINPUT=""
	USER_DISK=""
	einfo "Home install selected, please choose disk to partition "
	read -t 30 -p " [/dev/hda]: " UINPUT
	if  [ x"$UINPUT" == x"" ]; then
		USER_DISK="/dev/hda"
	elif [ x"$UINPUT" != x"" ]; then
		USER_DISK="$UINPUT"
	elif [ $? != 0 ]; then
		USER_DISK="/dev/hda"
	fi

	# Now call fdisk with user supplied argument
	einfo "Calling fdisk for partitioning"
	fdisk $USER_DISK

	# Check return code, restart this function if no good
	if [ $? = 0 ]; then
		einfo "Disk partitoned sucessfully"
		hdparm -c1 -d1 -A1 -m16 -u1 -a 64 $USER_DISK
	else
		ewarn "Error partitioning disk, repeating"
		sleep 5
		do_home
	fi
}

function do_home_fs() {
	ROOT_PART=""
	ROOT_FS=""
	BOOT_PART=""
	SWAP_PART=""

	# Now we have to get the filesystem layout off the user
	# / first
	echo -e "\n"
	einfon "Please enter the partion of the / filesystem (eg /dev/hdax):"
	read ROOT_PART
	einfon "Please enter the filesystem of / "
	read -p "[ext3|xfs]: " ROOT_FS
	if [ x"$ROOT_FS" != x"xfs" ] && [ x"$ROOT_FS" != x"REISERFS" ] && [ x"$ROOT_FS" != x"ext3" ] && [ x"$ROOT_FS" != x"EXT3" ]; then
		ewarn "Invalid filesystem selected, must be xfs or ext3"
		sleep 5
		do_home_fs
	else
		ebegin "Creating $ROOT_FS filesystem on $ROOT_PART"
		if [ x"$ROOT_FS" == x"xfs" ] || [ x"$ROOT_FS" == x"REISERFS" ]; then
			mkfs.xfs -f $ROOT_PART
		else
			mkfs.ext2 -q -j $ROOT_PART
		fi
		if [ $? = 0 ]; then
			eend
		else
			eend 1
			eerror "Error creating $ROOT_FS filesystem on $ROOT_PART"
			exit
		fi
	fi

	# Now SWAP
	echo -e "\n"
	einfon "Please enter the partition to be used as SWAP (eg /dev/hdax): "
	read SWAP_PART
	ebegin "Creating SWAP on $SWAP_PART"
	mkswap $SWAP_PART
	if [ $? = 0 ]; then
		eend
	else 
		eend 1
		eerror "Error creating SWAP on $SWAP_PART"
		exit
	fi

	# Now boot
	echo -e "\n"
	einfon "Please enter the partition for the /boot filesystem (ext2): "
	read BOOT_PART
	ebegin "Creating ext2 filesystem on $BOOT_PART"
	mkfs.ext2 -q $BOOT_PART
	if [ $? = 0 ]; then
		eend
	else 
		eend 1
		eerror "Error creating /boot on $BOOT_PART"
		exit
	fi
	
	einfo "Base filesystems created, manually generate any others after install has finished"

	ebegin "Activating swap"
	`swapon $SWAP_PART`
	if [ $? = 0 ]; then
		eend
	else 
		eend 1
		eerror "Error activating swap on $SWAP_PART"
		exit
	fi

	# Mount filesystems

	ebegin "Mounting / at /mnt/gentoo"
	if [ ! -d /mnt/gentoo ]; then
		mkdir -p /mnt/gentoo
		if [ $? != 0 ]; then
			eend 1
			eerror "Error making /mnt/gentoo directory"
			exit
		fi
	fi
	`mount $ROOT_PART /mnt/gentoo`
	if [ $? = 0 ]; then
		eend
	else
		eend 1
		eerror "Error mounting $ROOT_PART at /mnt/gentoo"
		exit
	fi

	ebegin "Mounting /boot at /mnt/gentoo/boot"
	`mkdir /mnt/gentoo/boot`
	if [ $? = 0 ]; then
		eend
	else
		eend 1
		error "Error making /mnt/gentoo/boot"
		exit
	fi
	`mount $BOOT_PART /mnt/gentoo/boot`
	if [ $? = 0 ]; then
		eend
	else 
		eend 1 
		error "Error mounting $BOOT_PART at /mnt/gentoo/boot"
		exit
	fi
	
	return 0
}


# Work install

function do_work() {

	# Check to see if we've got a hard drive at hda

	ebegin "Detecting IDE hard drive"
	if [ -e /proc/ide/hda/ ]; then
		HDA_MEDIA=`cat /proc/ide/hda/media`
		if [ $HDA_MEDIA == "disk" ]; then
			IDE=1
			eend 
		else
			eend 1
		fi
	fi

	ebegin "Detecting SCSI devices"
	if [ -e /proc/scsi/scsi ]; then
		SDA_MEDIA=`grep Direct-Access /proc/scsi/scsi`
		if [ x"$SDA_MEDIA" != x"" ]; then
			SCSI=1
			eend
		else
			eend 1
		fi
	fi

	if [ $(($IDE+$SCSI)) == 2 ] ; then
		eerror "Both SCSI and IDE hard drives found, can't determine boot device."
		eerror "Please shut down machine, disconnect the unwanted boot device and"
		eerror "re-install."
		exit	
	fi

	if [ $IDE == 1 ]; then
		DISK="/dev/hda"
	elif [ $SCSI == 1 ]; then
		DISK="/dev/sda"
	else
		eerror "No hard drives detected, aborting install"
		exit
	fi

	# Calculate disk geometries and swap size

	ebegin "Calculating swap size from installed RAM"
	MEM=`cat /proc/meminfo | grep MemTotal: | tr -s ' ' | cut -d' ' -f2`
	if [ x"$MEM" == x"" ]; then
		eend 1
		eerror "Can't detect amount of installed RAM, exiting"
		exit
	fi

	if [ $((2*$MEM*1024)) -gt $MAX_SWAP ]; then 
		SWAP=$MAX_SWAP
	else
		SWAP=$((2*$MEM*1024))
	fi

	if [ $MIN_SWAP -gt $SWAP ]; then
		SWAP=$MIN_SWAP
	fi

	eend

	ebegin "Determining disk size and geometry"

	# Find number of bytes per sector

	BPS=`sfdisk -l $DISK | grep Units | tr -s ' ' | cut -d' ' -f5`
	if [ x"$BPS" == x"" ]; then
	  # if disk is brandnew put a partition on it (second chance)
	  echo ",,83" | sfdisk $DISK
	  BPS=`sfdisk -l $DISK | grep Units | tr -s ' ' | cut -d' ' -f5`
	fi
	if [ x"$BPS" == x"" ]; then
		eend 1
		eerror "Can't determine disk geometry"
		exit
	fi

	BPB=`sfdisk -l $DISK | grep Units | tr -s ' ' | cut -d' ' -f9`
	if [ x"$BPB" == x"" ]; then
		eend 1
		eerror "Can't determine disk geometry"
		exit
	fi


	# Determine total disk size in bytes
	DISK_BLOCKS=`sfdisk -s $DISK`
	if [ x"$DISK_BLOCKS" == x"" ]; then
		eend 1
		eerror "Can't determine disk blocks"
		exit
	fi
	DISK_SIZE=$(($DISK_BLOCKS*$BPB))
	if [ x"$DISK_SIZE" == x"" ]; then
		eend 1
		eerror "Can't determine disk blocks"
		exit
	fi


	eend

	# Need to see if there is an existing /research partition.  The best we can do
	# here is look for /dev/hda to contain an existing linux partition

	OUT=""
	OUT=`sfdisk -l $DISK | grep Linux`
	if [ x"$OUT" != x"" ]; then
		ewarn "Existing Linux partitions found!"
		muyfm
		ewarn "Too late sucker, the disk is toast now"
	fi

	# Better check for NTFS partitions too.....
	OUT=""
	OUT=`sfdisk -l $DISK | grep NTFS`
	if [ x"$OUT" != x"" ]; then
		ewarn "Existing NTFS partitions found!"
		muyfm
		ewarn "Too late sucker, the disk is toast now"
	fi


	# Create partition table

	einfo "Creating partition table with no research partition"
	sfdisk -D $DISK << EOF > /dev/null 2>&1
0,$(($BOOT_SIZE/$BPS)),L
,$(($SWAP/$BPS)),S
,,,*
;
;
EOF

#echo "BPS="$BPS" SWAP="$SWAP" BOOT_SIZE="$BOOT_SIZE
#echo "BPB="$BPB
#echo "Blocks="$(($SWAP/$BPS))

	# Not a particularly thorough test of the success of the partitioning but at
	# least it will tell us if anything heinous has happened.
	ebegin "Partition creation success?"
	`sfdisk -V -q $DISK`
	if [ $? = 0 ]; then
		eend
	else
		eend 1
		eerror "Partition creation failed, exiting"
		exit
	fi

	# Create filesystems, activate swap and mount devices
        export PATH=/sbin/:$PATH
	ebegin "Creating $BOOT_FS on /boot"
	FS_CMD=""
	if [ $BOOT_FS == "ext2" ]; then
		FS_CMD="mkfs.ext2 -q ${DISK}1"
	elif [ $BOOT_FS == "ext3" ]; then
		FS_CMD="mkfs.ext2 -q -j ${DISK}1"
	else
		eend 1
		eerror "$BOOT_FS filesystem not supported on /boot"
		exit
	fi

	var0=0
	LIMIT=100
	while [ "$var0" -lt "$LIMIT" ]
	do
		echo "do "$FS_CMD
		`$FS_CMD`
		if [ $? = 0 ]; then
			var0=$LIMIT
			echo "Format OK"
		else
			sleep 3
			eerror "Error creating $BOOT_FS on /boot - retry "$var0
			var0=$(($var0+1))
			sleep 2
		fi
	done

	if [ "$var0" = "$LIMIT" ]; then
		eend
	else
		eend 1
		eerror "Error creating $BOOT_FS on /boot"
		exit
	fi

	ebegin "Creating $ROOT_FS on /"
	FS_CMD=""
	if [ $ROOT_FS == "ext3" ]; then
		FS_CMD="mkfs.ext2 -q -j ${DISK}3"
	elif [ $ROOT_FS == "xfs" ]; then
		FS_CMD="mkfs.xfs -f ${DISK}3"
	else
		eend 1
		eerror "$ROOT_FS filesystem not supported on /"
		exit
	fi

	`$FS_CMD > /dev/null 2>&1`
	if [ $ROOT_FS == "ext3" ]; then
		if [ $? = 0]; then
			eend
		else
			eend 1
			eerror "Error creating $ROOT_FS on /"
			exit
		fi
	elif [ $ROOT_FS == "xfs" ]; then
		`fsck.xfs -a ${DISK}3 > /dev/null 2>&1`
		if [ $? = 0 ]; then
			eend
		else
			eend 1
			eerror "Error creating $ROOT_FS on /"
			exit
		fi
	else
		eend 1
		eerror "$ROOT_FS filesystem not supported on /"
	fi

	if [ $RE_FLAG = 1 ]; then
		ebegin "Creating $RE_FS on /research"
		FS_CMD=""
		if [ $RE_FS == "ext3" ]; then
			FS_CMD="mkfs.ext2 -q -j ${DISK}4"
		elif [ $RE_FS == "xfs" ]; then
			FS_CMD="mkfs.xfs -f ${DISK}4"
		else
			eend 1
			eerror "$RE_FS filesystem not supported on /research"
			exit
		fi

		`$FS_CMD > /dev/null 2>&1`
		if [ $RE_FS == "ext3" ]; then
			if [ $? = 0 ]; then
				eend
			else
				eend 1
				eerror "Error creating $RE_FS on /research"
				exit
			fi
		elif [ $RE_FS == "xfs" ]; then
			`fsck.xfs -a ${DISK}4 > /dev/null 2>&1`
			if [ $? = 0 ]; then
				eend
			else
				eend 1
				eerror "Error creating $RE_FS on /research"
				exit
			fi
		else
			eend 1
			eerror "$RE_FS filesystem not supported on /research"
		fi
	fi

	# Activate swap

	ebegin "Making swap on ${DISK}2"
	`mkswap ${DISK}2 > /dev/null 2>&1`
	if [ $? = 0 ]; then
		eend
	else
		eend 1
		eerror "Error making swap device on ${DISK}2"
		exit
	fi

	ebegin "Activating swap"
	`swapon ${DISK}2`
	if [ $? = 0 ]; then
		eend
	else 
		eend 1
		eerror "Error activating swap on ${DISK}2"
		exit
	fi

	# Mount filesystems

	ebegin "Mounting / at /mnt/gentoo"
	if [ ! -d /mnt/gentoo ]; then
		mkdir -p /mnt/gentoo
		if [ $? != 0 ]; then
			eend 1
			eerror "Error making /mnt/gentoo directory"
			exit
		fi
	fi
	`mount ${DISK}3 /mnt/gentoo`
	if [ $? = 0 ]; then
		eend
	else
		eend 1
		eerror "Error mounting ${DISK}3 at /mnt/gentoo"
		exit
	fi

	ebegin "Mounting /boot at /mnt/gentoo/boot"
	`mkdir /mnt/gentoo/boot`
	if [ $? = 0 ]; then
		eend
	else
		eend 1
		error "Error making /mnt/gentoo/boot"
		exit
	fi
	`mount ${DISK}1 /mnt/gentoo/boot`
	if [ $? = 0 ]; then
		eend
	else 
		eend 1 
		error "Error mounting ${DISK}1 at /mnt/gentoo/boot"
		exit
	fi

	return 0
}

#
# Main
#

# Firstly decide whether this is a work or home install

do_post

# Set up networking

#ebegin "Setting up network via DHCP"

#dhcpcd -T
#NET=`ifconfig | grep addr:10.1.1`
#if [ x"$NET" != x"" ]; then
#	eend
#fi

# Do work or home install

if [ $WORK -eq 2 ]; then
	/mnt/cdrom/setup_files/doformatlvm
elif [ $WORK -eq 1 ]; then
	do_work
else
	do_home_part
	do_home_fs
fi

mount | grep portage
if [ $? = 1 ]
then
	eend 1
	eerror "Error creating filesystem"
	exit
fi

# Mount filesystem from pxe install machine (start the portmapper first)
#/etc/init.d/portmap start
#ebegin "Mounting remote filesystem from pxe server"
#mkdir -p /mnt/pxe
#mount $REM_FS /mnt/pxe
#if [ $? = 0 ]; then
#	eend
#else
#	eend 1
#	eerror "Error mounting $REM_FS"
#	exit
#fi

ebegin "Extracting $STAGE_THREE tarball to /mnt/gentoo (this may take a while)"
cd /mnt/gentoo
tar -xjpf $STAGE_THREE
if [ $? = 0 ]; then
	eend
else
	eend 1
	eerror "Error extracting stage1 tarball"
	exit
fi

ebegin "Extracting portage snapshot to /mnt/gentoo (this may take a while)"
cd /mnt/gentoo/usr
tar  -Jxpf $PORTAGE_SNAPSHOT
if [ $? = 0 ]; then
	eend
else
	eend 1
	eerror "Error extracting portage tarball"
	exit
fi

# Auskommentiert - wir machen bootstrap
# Copy the distfiles
#ebegin "Copying distfiles"
#mkdir -p /mnt/gentoo/usr/portage/distfiles
#cp -R /mnt/cdrom/distfiles /mnt/gentoo/usr/portage/distfiles
#if [ $? = 0 ]; then
#	eend
#else 
#	eend 1
#	eerror "Error copying distfiles"
#	exit
#fi

# Prepare chroot environment

einfo "Preparing chroot environment for second stage of install"

ebegin "Mounting proc into chroot environment"
mount -t proc proc /mnt/gentoo/proc
if [ $? = 0 ]; then
	eend
else
	eend 1
	eerror "Error mounting proc filesystem in chroot environment"
	exit
fi

ebegin "Mounting real /dev into chroot environment"
mount --rbind /dev /mnt/gentoo/dev
if [ $? = 0 ]; then
	eend
else
	eend 1
	eerror "Error mounting dev filesystem in chroot environment"
	exit
fi

ebegin "Mounting real /sys into chroot environment"
mount --rbind /sys /mnt/gentoo/sys
if [ $? = 0 ]; then
	eend
else
	eend 1
	eerror "Error mounting sys filesystem in chroot environment"
	exit
fi

ebegin "Copying resolv.conf to chroot environment"
if [ ! -f /etc/resolv.conv ]
then
  echo "nameserver `dhcpcd -U eth0 | grep domain_name_servers | grep -o '[0-9]\\+.*$'`" >/etc/resolv.conf
fi
cp /etc/resolv.conf /mnt/gentoo/etc/resolv.conf
if [ $? = 0 ]; then
	eend
else
	eend 1
	eerror "Error copying resolve.conf"
	exit
fi

ebegin "Copying default fstab to chroot environment"
cp /mnt/gentoo/etc/fstab /mnt/gentoo/etc/fstab.orig
cp /mnt/gentoo/etc/fstab /mnt/gentoo/etc/fstab.tmp
echo "# Generated part" >>/mnt/gentoo/etc/fstab.tmp
#sed "/# Generated part/r /root/fstab-new"  ${SETUP_FILES}/fstab >/mnt/gentoo/etc/fstab
sed "/# Generated part/r /mnt/gentoo/etc/fstab-new"  /mnt/gentoo/etc/fstab.tmp >/mnt/gentoo/etc/fstab
if [ $? = 0 ]; then
	eend
else
	eend 1
	eerror "Error copying fstab"
	exit
fi

ebegin "Copying default kernel to chroot environment"
cp ${SETUP_FILES}/k.cfg /mnt/gentoo/root/
if [ $? = 0 ]; then
	eend
else
	eend 1
	eerror "Error copying k.cfg"
	exit
fi

ebegin "Copying default make.conf to chroot environment"
mkdir -p /mnt/gentoo/etc/portage/repos.conf
cp ${SETUP_FILES}/gentoo.conf /mnt/gentoo/etc/portage/repos.conf
if [ $? = 0 ]; then
	eend
else
	eend 1
	eerror "Error copying make.conf"
	exit
fi

#sed -i "s/-pc-linux-gnu/${ARCH}-pc-linux-gnu/" /mnt/gentoo/etc/portage/make.conf


ebegin "Copying default locale.gen to chroot environment"
cat ${SETUP_FILES}/locale.gen >> /mnt/gentoo/etc/locale.gen
if [ $? = 0 ]; then
	eend
else
	eend 1
	eerror "Error appending locale.gen"
	exit
fi


ebegin "Copying zeroer"
cp ${SETUP_FILES}/zeroer  /mnt/gentoo/root/zeroer
if [ $? = 0 ]; then
	eend
else
	eend 1
	eerror "Error appending locale.gen"
	exit
fi


# Now copy into place the second stage install script and chroot into it
ebegin "Copy second stage install into place"
if [ $WORK -eq 1 ]; then
	cp ${SETUP_FILES}/chroot_install.sh /mnt/gentoo/chroot_install.sh
	sed -i "s/ROOT_PART/$ROOT_PART/" /mnt/gentoo/chroot_install.sh
	if [ $? = 0 ]; then
		eend
	else
		eend 1
		eerror "Error copying chroot_install.sh in to chroot environment"
	fi
else
	cp ${SETUP_FILES}/chroot_install.sh /mnt/gentoo/home_install.sh
	sed -i "s/ROOT_PART/$ROOT_PART/" /mnt/gentoo/home_install.sh
	if [ $? = 0 ]; then
		eend
	else
		eend 1
		eerror "Error copying chroot_install.sh in to chroot environment"
	fi
fi

ebegin "Setting keyboard to German"

sed -i "s/\"us\"/\"de-latin1-nodeadkeys\"/" /mnt/gentoo/etc/conf.d/keymaps

ebegin "Copying default locale.gen to chroot environment"
cp ${SETUP_FILES}/locale.gen /mnt/gentoo/etc/locale.gen
if [ $? = 0 ]; then
	eend
else
	eend 1
	eerror "Error copying locale.gen"
	exit
fi

# Set up hostname etc since the dhcpcd.ethx-info file isn't available inside the
# chroot environment
ebegin "Setting hostname and DNS domainname"
for TDEV in `ifconfig | grep -o "^[0-9a-z]\+" | grep -v lo `
do
  DHCPINFO=`dhcpcd -T $TDEV ` 
  if [ -z "$DOMAIN" ] && [ -n "$DHCPINFO" ]
  then
    DOMAIN=`echo "$DHCPINFO" | grep new_domain_name= | grep -o "[a-z0-9.-]\+$"`
    HOSTNAME=`echo "$DHCPINFO" | grep new_host_name= | grep -o "[a-z0-9.-]\+$"`
    DEV=$TDEV
  fi
done
if [ "$DEV" != "eth0" ]
then
  (cd /mnt/gentoo/etc/init.d ; ln -s net.lo net.$DEV )
fi
if [ -n "$HOSTNAME" ]
then
  sed -i "s/localhost/$HOSTNAME/" /mnt/gentoo/etc/conf.d/hostname
  echo "$HOSTNAME" >>/mnt/gentoo/etc/hostname
  if [ -n "$DOMAIN" ]
  then
    NEWIP=`echo "$DHCPINFO" | grep new_ip_address | egrep -o '[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}'`
    if [ -n "$NEWIP" ]
    then
      echo "$NEWIP	$HOSTNAME.$DOMAIN	$HOSTNAME" >> /mnt/gentoo/etc/hosts
      CIDR=`echo "$DHCPINFO" | grep new_subnet_cidr= | grep -o "[0-9]\+$"`
      DNSSERVER=`echo "$DHCPINFO" | grep new_domain_name_servers= | egrep -o '[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}'`
      GATEWAY=`echo "$DHCPINFO" | grep new_routers= | egrep -o '[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}'`
      echo "dns_servers_$DEV=\"$DNSSERVER\"" >> /mnt/gentoo/etc/conf.d/net
      echo "config_$DEV=( \"$NEWIP/$CIDR\" )" >> /mnt/gentoo/etc/conf.d/net
      echo "routes_$DEV=( \"default via $GATEWAY\" )" >> /mnt/gentoo/etc/conf.d/net
    fi
  fi
fi
if [ -n "$DOMAIN" ]
then
  echo "dns_domain_$DEV=\"$DOMAIN\"" >> /mnt/gentoo/etc/conf.d/net
fi
eend
einfo "Chrooting to hard drive image and continuing install"
if [ $WORK -eq 1 ]; then
	chroot /mnt/gentoo /chroot_install.sh
else
	chroot /mnt/gentoo /home_install.sh
fi
exit

# Once back from the chroot, reboot and we are all go

# Remove all NFS mounted filesystems.
#umount -t nfs -a

einfo "Reboot to complete install"
if [ $WORK -eq 1 ]; then
	# Check to see if chroot_install.sh script flagged any errors.  Cancel
	# reboot if so.
	if [ -f /mnt/gentoo/${ERR_FILE} ]; then
		rm /mnt/gentoo/${ERR_FILE}
		exit
	else
		reboot
	fi
else
	# Warn the user in there were any install errors
	if [ -f /mnt/gentoo/${ERR_FILE} ]; then
		ewarn "Warning - there were errors with the install!  Check before rebooting"
		rm /mnt/gentoo/${ERR_FILE}
	fi
	einfo "Please setup GRUB and /etc/fstab before rebooting"
	einfo "Entering chroot environment with /bin/bash so you can perform these tasks."
	einfo "Reboot when you are done."
	chroot /mnt/gentoo /bin/bash
fi
