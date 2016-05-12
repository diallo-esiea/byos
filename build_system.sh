#!/bin/bash -xv

CAT=/bin/cat
ECHO=/bin/echo
MKDIR=/bin/mkdir
MOUNT=/bin/mount
PWD=/bin/pwd
SED=/bin/sed
UMOUNT=/bin/umount

FDISK=/sbin/fdisk
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

USAGE="$(basename "$0") [options] [DEVICE] TARGET SUITE\n\n
\t\tDEVICE\t\n
\t\tTARGET\t\n\n
\t\tSUITE\t(lenny, squeeze, sid)\n
\toptions:\n
\t--------\n
\t\t-f=FILE, --file=FILE\tConfiguration file\n
\t\t-h, --help\t\tDisplay this message\n
\t\t-i=PATH, --include=PATH\tComma separated list of packages which will be added to download and extract lists\n
\t\t-m=PATH, --mirror=PATH\tCan be an http:// URL, a file:/// URL, or an ssh:/// URL\n
\t\t-p=PATH, --path=PATH\tPath to install system (default=./TARGET)\n
\t\t-v=VAR, --variant=VAR\tName of the bootstrap script variant to use (minbase, buildd, fakechroot, scratchbox)"

# Manage options 
for i in "$@"; do
  case $i in
    -h|--help)
      ${ECHO} -e ${USAGE}
      exit 0
      ;;

    -f=*|--file=*)
      # Convert relative path to absolute path
      if [[ ${i#*=} != /* ]]; then
        FILE=`${PWD}`/${i#*=}
      else
        FILE="${i#*=}"
      fi

      if [ ! -f ${FILE} ]; then
        ${ECHO} "File $FILE does not exists"
        exit 1
      fi

      # Parse configuration file
      source ${FILE}
      shift
      ;;

    -*|--*) # unknown option
      ${ECHO} -e ${USAGE}
      exit 1
      ;;
  
  esac
done

if [ $# -eq 2 ]; then
  TARGET=$1
  SUITE=$2
elif [ $# -eq 3 ]; then
  DEVICE=$1
  TARGET=$2
  SUITE=$3
else
  ${ECHO} -e ${USAGE}
  exit 1
fi

# Assign default value in case of no option
if [ -z "${DEST_PATH}" ]; then
  DEST_PATH=${TARGET}
fi

# Convert relative path to absolute path
for i in DEST_PATH; do 
  if [[ -n "${!i}" ]] && [[ ${!i} != /* ]]; then
    eval $i=`${PWD}`/${!i}
  fi
done

# Create DEST_PATH if not exists 
${MKDIR} -p ${DEST_PATH}

# Create and format boot partition
${SED} -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | ${FDISK} ${DEVICE}
o # clear the in memory partition table
n # new partition
p # primary partition
1 # partition number 1
  # default - start at beginning of disk 
+100M # 100 MB boot parttion
a # make a partition bootable
w # write the partition table
q # and we're done
EOF
${MKFS} --type=${TYPE} -L boot ${device}1; 

# Create Physical Volume (PVNAME) partition
${SED} -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | ${FDISK} ${DEVICE}
n # new partition
p # primary partition
2 # partion number 2
  # default, start immediately after preceding partition
  # default, extend partition to end of disk
w # write the partition table
q # and we're done
EOF

${PVCREATE} ${DEVICE}2
${VGCREATE} ${VGNAME} ${DEVICE}2

# Create and format Logical Volume (LVNAME)
for lvname in "${PART[@]}"; do
  set $lvname
  ${LVCREATE} -n $1 -L $2 ${VGNAME}
  ${MKFS} --type=$3 -L $1 /dev/mapper/${VGNAME}-$1; 
done

${LVCREATE} -n swap -L 1G ${VGNAME}
${MKSWAP} /dev/mapper/${VGNAME}-swap -L ${VGNAME}-swap

${MOUNT} /dev/mapper/${VGNAME}-root ${DEST_PATH}
${MKDIR} -p ${DEST_PATH}/{boot,home,srv,var}
${MOUNT} ${device}1 ${DEST_PATH}/boot
${MOUNT} /dev/mapper/${VGNAME}-home ${DEST_PATH}/home
${MOUNT} /dev/mapper/${VGNAME}-srv ${DEST_PATH}/srv
${MOUNT} /dev/mapper/${VGNAME}-var ${DEST_PATH}/var
${MKDIR} -p ${DEST_PATH}/var/log
${MOUNT} /dev/mapper/${VGNAME}-log ${DEST_PATH}/var/log

${FAKECHROOT} fakeroot ${DEBOOTSTRAP} --arch=${ARCH} --include=${INCLUDE} --variant=${VARIANT} ${SUITE} ${DEST_PATH} ${MIRROR}

# Set the hostname
${ECHO} ${HOSTNAME} > ${DEST_PATH}/etc/hostname

${CAT} > ${DEST_PATH}/etc/apt/sources.list << EOF
deb ${MIRROR} ${SUITE} main contrib non-free
deb-src ${MIRROR} ${SUITE} main contrib non-free

deb ${MIRROR} ${SUITE}-updates main contrib non-free
deb-src ${MIRROR} ${SUITE}-updates main contrib non-free

deb http://security.debian.org/debian-security ${SUITE}/updates main contrib non-free
deb-src http://security.debian.org/debian-security ${SUITE}/updates main contrib non-free
EOF

${CAT} > ${DEST_PATH}/etc/apt/apt.conf.d/60recommends <<EOF
APT::Install-Recommends "0";
APT::Install-Suggests "0";
EOF

${CAT} > ${DEST_PATH}/etc/fstab << EOF
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system>     <mount point>   <type>  <options>                 <dump>  <pass>
/dev/root           /               ${TYPE} noatime,errors=remount-ro   0       1
/dev/${VGNAME}/boot /boot           ${TYPE} defaults,noatime            1       2
/dev/${VGNAME}/home /home           ${TYPE} defaults,noatime            1       2
/dev/${VGNAME}/log  /var/log        ${TYPE} defaults,noatime            1       2
/dev/${VGNAME}/swap none            swap    swap                        0       0
/dev/${VGNAME}/srv  /srv            ${TYPE} defaults,noatime            1       2
/dev/${VGNAME}/ /var            ${TYPE} defaults,noatime            1       2
#cgroup             /sys/fs/cgroup  cgroup  defaults                    0       0
proc                /proc           proc    defaults                    0       0
sysfs               /sys            sysfs   defaults                    0       0
tmpfs               /tmp            tmpfs   defaults                    0       0
EOF

# Binding the virtual filesystems
#${MKDIR} -p ${TARGET}/{proc,sys,dev}
#for i in proc sys dev; do 
#  ${MOUNT} -o bind /$i ${TARGET}/$i; 
#done
#${MOUNT} -t proc none ${TARGET}/proc

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
#${UMOUNT} ${DEST_PATH}/{dev, proc, sys}

${UMOUNT} ${DEST_PATH}/var/log
${UMOUNT} ${DEST_PATH}/var
${UMOUNT} ${DEST_PATH}/tmp
${UMOUNT} ${DEST_PATH}/srv
${UMOUNT} ${DEST_PATH}/home
${UMOUNT} ${DEST_PATH}

#vgchange -a n

exit 0
