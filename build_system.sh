#!/bin/bash -xv

CAT=/bin/cat
CHMOD=/bin/chmod
ECHO=/bin/echo
LN=/bin/ln
MKDIR=/bin/mkdir
MOUNT=/bin/mount
PWD=/bin/pwd
RM=/bin/rm
SED=/bin/sed
UMOUNT=/bin/umount

BLKID=/sbin/blkid
FDISK=/sbin/fdisk
LVCREATE=/sbin/lvcreate
MKSWAP=/sbin/mkswap
MKE2FS=/sbin/mke2fs
PARTPROBE=/sbin/partprobe
PVCREATE=/sbin/pvcreate
VGCHANGE=/sbin/vgchange
VGCREATE=/sbin/vgcreate

APT_GET=/usr/bin/apt-get
CHROOT=/usr/sbin/chroot
DEBOOTSTRAP=/usr/sbin/debootstrap
DPKG_RECONFIGURE=/usr/sbin/dpkg-reconfigure
FAKECHROOT=/usr/bin/fakechroot
FIND=/usr/bin/find
GRUB_INSTALL=/usr/sbin/grub-install
GRUB_MKCONFIG=/usr/sbin/grub-mkconfig
#CHPASSWD=/usr/sbin/chpasswd

USAGE="$(basename "${0}") [options] [DEVICE] TARGET SUITE\n\n
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
  case ${i} in
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
        ${ECHO} "File ${FILE} does not exists"
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
  TARGET=${1}
  SUITE=${2}
elif [ $# -eq 3 ]; then
  DEVICE=${1}
  TARGET=${2}
  SUITE=${3}
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
    eval ${i}=`${PWD}`/${!i}
  fi
done

if [ -n "${PART}" ]; then
  # Set partition number and reset FSTAB
  id=1
  unset FSTAB

  # Get partition informations
  for part in "${PART[@]}"; do
    IFS=$' ' read name mount size type options dump pass <<< "${part}"
  
    if [ -n "${VGNAME}" ]; then
      if [ "${name}" != "boot" ]; then
        continue
      fi

      # Set partition number as the first partition
      id=1
    fi
  
    if [ ${id} -eq 1 ]; then
      # Create first partition
      ${SED} -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | ${FDISK} ${DEVICE}
      o        # clear the in memory partition table
      n        # new partition
      p        # primary partition
      ${id}    # partition number
               # default - start at beginning of disk 
      +${size} # partition size
      w        # write the partition table
      q        # and we're done
EOF
    elif [ $id -eq 4 ]; then
      # Create extended partition
      ${SED} -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | ${FDISK} ${DEVICE}
      n        # new partition
      e        # extended partition
               # default, start immediately after preceding partition
               # default, extend partition to end of disk
      n        # new partition
               # default, start immediately after preceding partition
      +${size} # partition size
      w        # write the partition table
      q        # and we're done
EOF

      # Increment partition number
      id=`expr ${id} + 1`
    elif [ ${id} -gt 4 ] && [ ${id} -lt 9 ]; then
      # Create partition in extended partition
      ${SED} -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | ${FDISK} ${DEVICE}
      n        # new partition
               # default, start immediately after preceding partition
      +${size} # partition size
      w        # write the partition table
      q        # and we're done
EOF
    elif [ ${id} -eq 9 ]; then
      ${ECHO} -e "Too many partitions (more than 8)"
      exit 1
    else
      # Create primary partition
      ${SED} -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | ${FDISK} ${DEVICE}
      n        # new partition
      p        # primary partition
      ${id}    # partion number
               # default, start immediately after preceding partition
      +${size} # partition size
      w        # write the partition table
      q        # and we're done
EOF
    fi

    # Informs kernel of partition table changes
    ${PARTPROBE}; sleep 1

    # Set bootable partition
    if [ "$1" == "boot" ]; then
      ${SED} -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | ${FDISK} ${DEVICE}
      a       # make a partition bootable
      ${size} # partion number
      w       # write the partition table
      q       # and we're done
EOF

      # Informs kernel of partition table changes
      ${PARTPROBE}; sleep 1
    fi

    # Format partition
    ${MKE2FS} -F -t ${type} -L ${name} ${DEVICE}${id}; 

    # Get UUID
    UUID=$(${BLKID} ${DEVICE}${id})
    UUID=${UUID#*UUID=\"}
    UUID=${UUID%%\"*}

    if [ "$name1}" == "root" ]; then
      FSTAB=("${DEVICE}${id} ${mount} ${type} ${options} ${dump} ${pass} ${UUID}" "${FSTAB[@]}")
    elif [ "${name}" != "swap" ]; then 
      FSTAB=("${FSTAB[@]}" "${DEVICE}${id} ${mount} ${type} ${options} ${dump} ${pass} ${UUID}")
    fi

    if [ -n "${VGNAME}" ]; then
      # Increment partition number
      id=`expr ${id} + 1`

      # Create Physical Volume (PVNAME) partition
      ${SED} -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | ${FDISK} ${DEVICE}
      n     # new partition
      p     # primary partition
      ${id} # partion number
            # default, start immediately after preceding partition
            # default, extend partition to end of disk
      w     # write the partition table
      q     # and we're done
EOF
  
      # Informs kernel of partition table changes
      ${PARTPROBE}; sleep 1
  
      # Create Physical Volume (VGNAME)
      ${PVCREATE} --force ${DEVICE}${id}
      ${VGCREATE} ${VGNAME} ${DEVICE}${id}
  
      # Create and format Logical Volume (LVNAME)
      for lvname in "${PART[@]}"; do
        IFS=$' ' read name mount size type options dump pass <<< "${lvname}"
        if [ "${name}" != "boot" ]; then
          ${LVCREATE} -n ${name} -L ${size} ${VGNAME}
          if [ "${name}" == "swap" ]; then
            ${MKSWAP} -L ${name} /dev/mapper/${VGNAME}-${name}
          else
            ${MKE2FS} -F -t ${type} -L ${name} /dev/mapper/${VGNAME}-${name}; 
            
            if [ "${name}" == "root" ]; then
              FSTAB=("/dev/mapper/${VGNAME}-${name} ${mount} ${type} ${options} ${dump} ${pass}" "${FSTAB[@]}")
            else 
              FSTAB=("${FSTAB[@]}" "/dev/mapper/${VGNAME}-${name} ${mount} ${type} ${options} ${dump} ${pass}")
            fi
          fi
        fi
      done

      # Add LVM package
      INCLUDE=${INCLUDE},lvm2

      break
    fi

    # Increment partition number
    id=`expr ${id} + 1`
  done
fi

# Mount all partitions
for fstab in "${FSTAB[@]}"; do
  IFS=$' ' read device mount type options dump pass uuid <<< "${fstab}"

  ${MKDIR} -p ${DEST_PATH}${mount}
  ${MOUNT} ${device} ${DEST_PATH}${mount}
done

# Add grub-common and grub2-common packages
INCLUDE=${INCLUDE},grub-common,grub2-common

${FAKECHROOT} fakeroot ${DEBOOTSTRAP} --arch=${ARCH} --include=${INCLUDE} --variant=${VARIANT} ${SUITE} ${DEST_PATH} ${MIRROR}

# Remplace symbolic link
IFS=$'\n'
LINKS=$(${FIND} ${DEST_PATH} -type l -lname "${DEST_PATH}*" -printf "%l\t%p\n")
for link in ${LINKS}; do
  IFS=$'\t' read path name <<< "$link"
  ${LN} -sfn ${path#${DEST_PATH}*} ${name}
done

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
EOF

for fstab in "${FSTAB[@]}"; do
  IFS=$' ' read device mount type options dump pass uuid <<< "${fstab}"

  # Check if UUID is available
  if [ -n "${uuid}" ]; then
    ${ECHO} -e "UUID=${uuid}\t${mount}\t${type}\t${options}\t${dump}\t${pass}" >> ${DEST_PATH}/etc/fstab
  else
    ${ECHO} -e "${device}\t${mount}\t${type}\t${options}\t${dump}\t${pass}" >> ${DEST_PATH}/etc/fstab
  fi
done

${CAT} >> ${DEST_PATH}/etc/fstab << EOF
#cgroup             /sys/fs/cgroup  cgroup  defaults                    0       0
proc                /proc           proc    defaults                    0       0
sysfs               /sys            sysfs   defaults                    0       0
tmpfs               /tmp            tmpfs   defaults                    0       0
EOF

# Binding the virtual filesystems
${MOUNT} --bind /dev ${DEST_PATH}/dev
${MOUNT} -t proc none ${DEST_PATH}/proc
${MOUNT} -t sysfs none ${DEST_PATH}/sys

# Create "chroot" script
${CAT} >> ${DEST_PATH}/chroot.sh << EOF
#!/bin/bash
# Install Grub
${GRUB_INSTALL} ${DEVICE}
${GRUB_MKCONFIG} -o /boot/grub/grub.cfg

# Configure locale
#export LANG=fr_FR.UTF-8
#${DPKG_RECONFIGURE} locales

# Create a password for root
#${ECHO} root:${ROOT_PASSWD} | ${CHPASSWD}

# Quit the chroot environment
exit
EOF
${CHMOD} +x ${DEST_PATH}/chroot.sh

# Entering the chroot environment
${CHROOT} ${DEST_PATH} ./chroot.sh 

# Remove "chroot" script
${RM} ${DEST_PATH}/chroot.sh

# Unbinding the virtual filesystems
#${UMOUNT} ${DEST_PATH}/{dev,proc,sys}

#if [ -n "${VGNAME}" ]; then
#  ${VGCHANGE} -a n
#fi

exit 0
