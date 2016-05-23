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
PARTPROBE=/sbin/partprobe
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

# Get boot partition informations
for part in "${PART[@]}"; do
  set $part
  if [ "$1" == "boot" ]; then
     break
  fi
done

# Check if boot partition informations are present
if [ "$1" != "boot" ]; then
  ${ECHO} "boot partition is not present"
  exit 1
fi

# Create boot partition
${SED} -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | ${FDISK} ${DEVICE}
o # clear the in memory partition table
n # new partition
p # primary partition
1 # partition number 1
  # default - start at beginning of disk 
+$3 # boot partition size
a # make a partition bootable
w # write the partition table
q # and we're done
EOF

# Informs kernel of partition table changes
${PARTPROBE}

# Format boot partition
${MKFS} --type=$4 -L $1 ${DEVICE}1; 

if [ -n "${VGNAME}" ]; then
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
  
  # Informs kernel of partition table changes
  ${PARTPROBE}
  
  # Create Physical Volume (VGNAME)
  ${PVCREATE} ${DEVICE}2
  ${VGCREATE} ${VGNAME} ${DEVICE}2
  
  # Create and format Logical Volume (LVNAME)
  for lvname in "${PART[@]}"; do
    set $lvname
    if [ "$1" != "boot" ]; then
      ${LVCREATE} -n $1 -L $3 ${VGNAME}
      if [ "$1" == "swap" ]; then
        ${MKSWAP} -L $1 /dev/mapper/${VGNAME}-$1
      else
        ${MKFS} --type=$4 -L $1 /dev/mapper/${VGNAME}-$1; 
      fi
    fi
  done

  # Add LVM package
  INCLUDE=${INCLUDE},lvm2
fi

# Mount all partitions
for dir in "${PART[@]}"; do
  set $dir
  if [ "$1" != "boot" ]  && [ "$1" != "swap" ]; then
    ${MKDIR} -p ${DEST_PATH}$2
    ${MOUNT} /dev/mapper/${VGNAME}-$1 ${DEST_PATH}$2
  fi
done

# Mount boot partition
${MKDIR} -p ${DEST_PATH}/boot
${MOUNT} ${DEVICE}1 ${DEST_PATH}/boot

${FAKECHROOT} fakeroot ${DEBOOTSTRAP} --arch=${ARCH} --include=${INCLUDE} --variant=${VARIANT} ${SUITE} ${DEST_PATH} ${MIRROR}

${CAT} > ${DEST_PATH}/etc/default/grub << EOF
# If you change this file, run 'update-grub' afterwards to update
# /boot/grub/grub.cfg.
# For full documentation of the options in this file, see:
#   info -f grub -n 'Simple configuration'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX="video=off elevator=deadline console=ttyS0,115200"

# Uncomment to disable graphical terminal (grub-pc only)
#GRUB_TERMINAL=console

# Uncomment if you don't want GRUB to pass "root=UUID=xxx" parameter to Linux
#GRUB_DISABLE_LINUX_UUID=true

GRUB_DISABLE_RECOVERY="true"

GRUB_TERMINAL=serial
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200 --stop=1"
EOF

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
/boot               /boot           ext2    noatime,errors=remount-ro   0       1
/dev/${VGNAME}/root /               ext4    defaults,noatime            1       2
/dev/${VGNAME}/home /home           ext4    defaults,noatime            1       2
/dev/${VGNAME}/log  /var/log        ext4    defaults,noatime            1       2
/dev/${VGNAME}/swap none            swap    swap                        0       0
/dev/${VGNAME}/srv  /srv            ext2    defaults,noatime            1       2
/dev/${VGNAME}/var  /var            ext2    defaults,noatime            1       2
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
#for i in proc sys dev; do 
#  ${UMOUNT} ${TARGET}/$i; 
#done

#${UMOUNT} ${DEST_PATH}/var/log
#${UMOUNT} ${DEST_PATH}/var
#${UMOUNT} ${DEST_PATH}/srv
#${UMOUNT} ${DEST_PATH}/home
#${UMOUNT} ${DEST_PATH}/boot
#${UMOUNT} ${DEST_PATH}

#vgchange -a n

exit 0
