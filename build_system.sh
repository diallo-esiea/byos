#!/bin/bash -xv

CAT=/bin/cat
ECHO=/bin/echo
MKDIR=/bin/mkdir
MOUNT=/bin/mount
UMOUNT=/bin/umount

LVCREATE=/sbin/lvcreate
MKSWAP=/sbin/mkswap
MKFS=/sbin/mkfs
PVCREATE=/sbin/pvcreate
VGCREATE=/sbin/vgcreate

APT_GET=/usr/bin/apt-get
CHROOT=/usr/sbin/chroot
DEBOOTSTRAP=/usr/sbin/debootstrap
DPKG_RECONFIGURE=/usr/sbin/dpkg-reconfigure
FAKECHROOT=/usr/bin/fakechroot
PASSWD=/usr/bin/passwd

ARCH=amd64    		# i386, amd64
HOSTNAME=debian
INCLUDE=grub2,locales
MIRROR=http://mirror.lrp/debian
PVNAME=/dev/sdx
SUITE=sid           # jessie, wheezy, sid, stable, testing, unstable
# Attention le fakeroot ne fonctionne pas avec Jessie le 18/04/2016 (cf. https://github.com/dex4er/fakechroot/pull/37)
# => pour Jessie, remplacer FAKEROOT=<chaine vide> et FAKECHROOT=<chaine vide> et lancer build_system en root ou sudo
TARGET=debian
TYPE=ext4
VARIANT=minbase     # minbase, buildd, fakechroot, scratchbox
VGNAME=pcengines

USAGE="$(basename "$0") [options] SUITE TARGET\n\n
\t\tSUITE\t(lenny, squeeze, sid)\n
\t\tTARGET\t\n\n
\toptions:\n
\t--------\n
\t\t-i, --include\tComma separated list of packages which will be added to download and extract lists\n
\t\t-m, --mirror\tCan be an http:// URL, a file:/// URL, or an ssh:/// URL\n
\t\t-v, --variant\tName of the bootstrap script variant to use (minbase, buildd, fakechroot, scratchbox)"

for i in "$@"; do
  case $i in
    -h|--help)
      ${ECHO} -e ${USAGE}
      exit 0
      ;;

  esac
done

#${PVCREATE} ${PVNAME}
#${VGCREATE} ${VGNAME} ${PVNAME}
#${LVCREATE} -n root -L 10G ${VGNAME}
#${LVCREATE} -n boot -L 200M ${VGNAME}
#${LVCREATE} -n var -L 20G ${VGNAME}
#${LVCREATE} -n log -L 10G ${VGNAME}
#${LVCREATE} -n home -L 10G ${VGNAME}
#${LVCREATE} -n swap -L 1G ${VGNAME}
#${LVCREATE} -n srv -l 100%FREE ${VGNAME}

#for d in root boot var log tmp home srv; do 
#  ${MKFS} --type=${TYPE} /dev/mapper/${VGNAME}-${d} -L ${VGNAME}-${d}; 
#done
#${MKSWAP} /dev/mapper/${VGNAME}-swap -L ${VGNAME}-swap

#${MOUNT} /dev/mapper/${VGNAME}-root ${TARGET}
#${MKDIR} -p ${TARGET}/{boot,var,home}
#${MOUNT} /dev/mapper/${VGNAME}-boot ${TARGET}/boot
#${MOUNT} /dev/mapper/${VGNAME}-home ${TARGET}/home
#${MOUNT} /dev/mapper/${VGNAME}-var ${TARGET}/var
#${MKDIR} -p ${TARGET}/var/log
#${MOUNT} /dev/mapper/${VGNAME}-log ${TARGET}/var/log

# Binding the virtual filesystems
#${MKDIR} -p ${TARGET}/{proc,sys,dev}
#for i in proc sys dev; do 
#  ${MOUNT} -o bind /$i ${TARGET}/$i; 
#done
#${MOUNT} -t proc none ${TARGET}/proc

${FAKECHROOT} fakeroot ${DEBOOTSTRAP} --arch=${ARCH} --include=${INCLUDE} --variant=${VARIANT} ${SUITE} ${TARGET} ${MIRROR}

# Set the hostname
${ECHO} ${HOSTNAME} > ${TARGET}/etc/hostname

${CAT} > ${TARGET}/etc/apt/sources.list << EOF
deb ${MIRROR} ${SUITE} main contrib non-free
deb-src ${MIRROR} ${SUITE} main contrib non-free

deb ${MIRROR} ${SUITE}-updates main contrib non-free
deb-src ${MIRROR} ${SUITE}-updates main contrib non-free

deb http://security.debian.org/debian-security ${SUITE}/updates main contrib non-free
deb-src http://security.debian.org/debian-security ${SUITE}/updates main contrib non-free
EOF

${CAT} > ${TARGET}/etc/apt/apt.conf.d/60recommends <<EOF
APT::Install-Recommends "0";
APT::Install-Suggests "0";
EOF

${CAT} > ${TARGET}/etc/fstab << EOF
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system>     <mount point>   <type>  <options>         <dump>  <pass>
/dev/root           /               ${TYPE} noatime,errors=remount-ro 0 1
proc                /proc           proc    defaults          0       0
/dev/${VGNAME}/boot /boot           ${TYPE} defaults,noatime  1       2
/dev/${VGNAME}/home /home           ${TYPE} defaults,noatime  1       2
tmpfs               /tmp            tmpfs   defaults          0       0
/dev/${VGNAME}/srv  /srv            ${TYPE} defaults,noatime  1       2
sysfs               /sys            sysfs   defaults          0       0
#cgroup             /sys/fs/cgroup  cgroup  defaults          0       0
/dev/${VGNAME}/swap none            swap    swap              0       0
/dev/${VGNAME}/var  /var            ${TYPE} defaults,noatime  1       2
/dev/${VGNAME}/log  /var/log        ${TYPE} defaults,noatime  1       2
EOF

# Entering the chroot environment
#${FAKECHROOT} ${CHROOT} ${TARGET} /bin/bash 

# Configure locale
#export LANG=fr_FR.UTF-8
#${DPKG_RECONFIGURE} locales

# Create a password for root
#${PASSWD}

# Update Debian package database:
#${APT_GET} update

# Quit the chroot environment
#${EXIT}

# Unbinding the virtual filesystems
#${UMOUNT} ${TARGET}/var/log
#${UMOUNT} ${TARGET}/{boot, var, home, tmp}
#${UMOUNT} ${TARGET}/{dev, proc, sys}
#${UMOUNT} ${TARGET}

#vgchange -a n

exit 0
