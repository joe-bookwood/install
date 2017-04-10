#!/bin/bash
# 
# Gentoo automated install script, second stage in chroot environment
#
# NOTE: this script is under CVS control
#

SYSTEMD=0
function startService() {
   if [ $SYSTEMD -eq 1 ]
   then
     systemctl enable $1.service
   else
     rc-config add $1
   fi
}
# Setup chroot environment
env-update
source /etc/profile
export PS1="(chroot) $PS1" 
#source /sbin/functions.sh

CPUS=`cat /proc/cpuinfo | grep ^processor | wc -l`
if [ $CPUS -gt 1 ]
then
    N=$(($CPUS * 2))
    AFB=" --load-average=${N} -j ${N} "
fi
MARCH=`gcc -march=native -Q --help=target | grep march | awk '{print($NF)}'`

if [ $SYSTEMD -eq 1 ]
then
  PVER=`eselect profile list | egrep [0-9]/systemd$ | egrep -o "\[[0-9]+" | egrep -o "[0-9]+$"`
  emerge --deselect sys-fs/udev
  euse  -E systemd
else
  PVER=1
fi

eselect profile set $PVER

sed -i "s/=native/=${MARCH}/" /etc/make.conf

echo "Starting second stage install from chroot environment"
emerge --sync 
if [ $? -eq 1 ]
then
  echo "emerge sync fails"
  exit

fi
emerge portage 
emerge app-portage/gentoolkit

#emerge -NDu world
emerge -NDu -j 4 --keep-going y $AFB @world
if [ $? -eq 1 ]
then
  echo "failed emerge -NDu "
  exit
fi

#echo "Emerge system"
#emerge --emptytree system
#if [ $? -eq 1 ]
#then
#  GERROR="${GERROR} SYSTEM"
#  echo "Emerge system Error"
#fi
echo "Emerge NTPD"
emerge $AFB ntp
if [ $? -eq 1 ]
then
  GERROR="${GERROR} NTPD"
fi
startService ntpd default
echo "Emerge lvm2"
emerge  $AFB lvm2
if [ $? -eq 1 ]
then
  GERROR="${GERROR} LVM2"
fi
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
ntpdate 10.1.1.254
hwclock --systohc
emerge gentoo-sources
if [ $? -eq 1 ]
then
  GERROR="${GERROR} KERNEL"
fi
emerge $AFB genkernel-next
if [ $? -eq 1 ]
then
  GERROR="${GERROR} GENKERNEL"
fi
emerge $AFB syslog-ng
if [ $? -eq 1 ]
then
  GERROR="${GERROR} SYSLOG"
fi
startService syslog-ng default
emerge $AFB vixie-cron
if [ $? -eq 1 ]
then
  GERROR="${GERROR} VIXIECRON"
fi
startService vixie-cron default
emerge $AFB xfsprogs
if [ $? -eq 1 ]
then
  GERROR="${GERROR} XFSPROGS"
fi
emerge $AFB grub
if [ $? -eq 1 ]
then
  GERROR="${GERROR} GRUB"
fi
emerge $AFB vim
if [ $? -eq 1 ]
then
  GERROR="${GERROR} VIM"
fi
emerge $AFB iproute2
if [ $? -eq 1 ]
then
  GERROR="${GERROR} IPROUTE"
fi
emerge $AFB tcpdump
if [ $? -eq 1 ]
then
  GERROR="${GERROR} TCPDUMP"
fi
emerge $AFB dhcpcd
if [ $? -eq 1 ]
then
  GERROR="${GERROR} DHCPD"
fi
emerge $AFB mailx
if [ $? -eq 1 ]
then
  GERROR="${GERROR} MAILX"
fi
emerge $AFB app-misc/screen
if [ $? -eq 1 ]
then
  GERROR="${GERROR} SCREEN"
fi
emerge $AFB bind-tools
if [ $? -eq 1 ]
then
  GERROR="${GERROR} BINDTOOLS"
fi
emerge $AFB htop
if [ $? -eq 1 ]
then
  GERROR="${GERROR} HTOP"
fi
emerge $AFB nfs-utils
if [ $? -eq 1 ]
then
  GERROR="${GERROR} NFS"
fi
emerge $AFB acpid
if [ $? -eq 1 ]
then
  GERROR="${GERROR} ACPID"
fi
emerge $AFB gentoolkit
if [ $? -eq 1 ]
then
  GERROR="${GERROR} gentoolkit"
fi
emerge $AFB gentoo-bashcomp
if [ $? -eq 1 ]
then
  GERROR="${GERROR} gentoo-bashcomp"
fi
emerge $AFB dev-vcs/git
if [ $? -eq 1 ]
then
  GERROR="${GERROR} git"
fi
emerge $AFB mlocate
if [ $? -eq 1 ]
then
  GERROR="${GERROR} mlocate"
fi

#echo "use_lvmetad = 1" >> /etc/lvm/lvm.conf

# Add services
startService lvm boot
startService acpid default
startService nfs default
startService sshd default
startService lvm2-monitor default
if [ $SYSTEMD -eq 1 ]
then
  startService systemd-networkd default
  SYSTEMDGRUB=" init=/usr/lib/systemd/systemd"
  localectl set-keymap de-latin1-nodeadkeys
fi

sed -i 's/#SYMLINK=\"no\"/SYMLINK=\"yes\"/g' /etc/genkernel.conf

cp /proc/mounts /etc/mtab
cat /proc/mdstat | grep blocks
if [ $? -eq 0 ]
then
  emerge dmraid
  echo "GRUB_CMDLINE_LINUX=\"dolvm dodmraid doscsi transparent_hugepage=always real_root=/dev/mapper/vg1-root$SYSTEMDGRUB\"" >> /etc/default/grub
  genkernel --lvm --dmraid --symlink --menuconfig all
else
  echo "GRUB_CMDLINE_LINUX=\"dolvm doscsi transparent_hugepage=always real_root=/dev/mapper/vg1-root$SYSTEMDGRUB\"" >> /etc/default/grub
  genkernel --lvm --symlink --menuconfig all
fi

grub2-install /dev/ROOTPART
grub2-mkconfig -o /boot/grub/grub.cfg

echo "Fehler: ${GERROR}"
echo "Fehler: ${GERROR}" >/tmp/builderrors
exit

