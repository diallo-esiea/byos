#!/bin/bash -xv

CAT=/bin/cat
CP=/bin/cp
CHMOD=/bin/chmod
ECHO=/bin/echo
LN=/bin/ln
MKDIR=/bin/mkdir
MOUNT=/bin/mount
PWD=/bin/pwd
RM=/bin/rm
SED=/bin/sed
SYSTEMCTL=/bin/systemctl
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
CHPASSWD=/usr/sbin/chpasswd
CHROOT=/usr/sbin/chroot
DEBOOTSTRAP=/usr/sbin/debootstrap
DPKG_RECONFIGURE=/usr/sbin/dpkg-reconfigure
FAKECHROOT=/usr/bin/fakechroot
FIND=/usr/bin/find
GRUB_INSTALL=/usr/sbin/grub-install
GRUB_MKCONFIG=/usr/sbin/grub-mkconfig
LOCALE_GEN=/usr/sbin/locale-gen
LOCALE_UPDATE=/usr/sbin/update-locale
UPDATE_GRUB=/usr/sbin/update-grub
UPDATE_INITRAMFS=/usr/sbin/update-initramfs

KERNEL_BUILD=./script/build_kernel.sh
SYSTEM_BUILD=./script/build_system.sh

USAGE="$(basename "${0}") [options] <COMMAND> DEVICE CONFIG VERSION\n\n
\tDEVICE\tTarget device name\n
\tCONFIG\tLinux kernel config file\n
\tVERSION\tKernel version to build\n\n
\tCOMMAND:\n
\t--------\n
\t\tbuild\tBuild whole system\n
\t\tupdate\tUpdate kernel\n\n
\tbuild options:\n
\t--------------\n
\t\t-s=NAME, --suite=NAME\tName of the suite (lenny, squeeze, sid,...) (default=stable)\n
\t\t-t=NAME, --target=NAME\tName of the target (default=debian)\n\n
\tkernel options:\n
\t--------------\n
\t\t-a=ALT, --alt=ALT\tAlternative Configuration (config, menuconfig, oldconfig, defconf, alldefconfig, allnoconfig,...)\n
\t\t-d, --deb\t\tCreate Debian package archive\n
\t\t-g=PATCH, --grsec=PATCH\tGrsecurity patch\n
\t\t-i=PATCH, --git=PATCH\tGit path to get the kernel archive\n
\t\t-l=PATH, --local=PATH\tPath to get the kernel archive (instead of official Linux Kernel Archives URL)\n
\t\t-n, --nodelete\t\tKeep temporary files\n
\t\t-t=PATH, --temp=PATH\tTemporary folder\n\n
\toptions:\n
\t--------\n
\t\t-f=FILE, --file=FILE\tConfiguration file\n
\t\t-h, --help\t\tDisplay this message\n
\t\t-i=PATH, --include=PATH\tComma separated list of packages which will be added to download and extract lists\n
\t\t-m=PATH, --mirror=PATH\tCan be an http:// URL, a file:/// URL, or an ssh:/// URL\n
\t\t-p=PATH, --path=PATH\tPath to install system (default=./byos)\n
\t\t-v=VAR, --variant=VAR\tName of the bootstrap script variant to use (minbase, buildd, fakechroot, scratchbox)"

build_kernel () {
  # Create DEST_PATH if not exists 
  ${MKDIR} -p ${DEST_PATH}
  
  pushd ${TMP_PATH} > /dev/null || exit 1
  
  if [ -n "${GIT_PATH}" ]; then
    pushd ${GIT_PATH} > /dev/null || exit 1
    
    # Remove untracked directories and untracked files
    ${GIT} clean -d --force --quiet 
  
    # Checkout a branch version
    ${GIT} checkout v${KERNEL_VERSION}
  else
    KERNEL_NAME=linux-${KERNEL_VERSION}
    KERNEL_TAR=${KERNEL_NAME}.tar
    
    if [ -n "${KERNEL_PATH}" ]; then
      # Check if kernel version exists
      if [ ! -f ${KERNEL_PATH}/${KERNEL_TAR} ]; then
        ${ECHO} "Kernel version does not exist" >&2
        exit 1
      fi
    
      # Decompress kernel archive
      ${TAR} -xf ${KERNEL_PATH}/${KERNEL_TAR} -C ${TMP_PATH}
    else
      # kernel.org branch url and target files
      KERNEL_URL=https://www.kernel.org/pub/linux/kernel/v${KERNEL_VERSION/%.*/.x}
      
      # Check if BOTH kernel version AND signature file exist
      ${WGET} -c --spider ${KERNEL_URL}/${KERNEL_TAR}.{sign,xz}
      
      if [ $? -ne 0 ]; then
        ${ECHO} "Kernel version does not exist" >&2
        exit 1
      fi
      
      # Download kernel AND signature
      ${WGET} -c ${KERNEL_URL}/${KERNEL_TAR}.{sign,xz}
    
      # Uncompressing kernel archive
      ${UNXZ} ${KERNEL_TAR}.xz
      
      # Initialize GPG keyrings
      ${PRINTF} "" | ${GPG}
      
      # Download GPG keys
      GPG_KEYSERVER=keyserver.ubuntu.com 
      GPG_KEY=`${GPG} --verify ${KERNEL_TAR}.sign 2>&1 | \
               ${AWK} '{print $NF}' | \
               ${SED} -n '/\([0-9]\|[A-H]\)$/p' | \
               ${SED} -n '1p'`
      ${GPG} --keyserver ${GPG_KEYSERVER} --recv-keys ${GPG_KEY}
      
      # Verify kernel archive against signature file
      ${GPG} --verify ${KERNEL_TAR}.sign
    
      # Decompress kernel archive
      ${TAR} -xf ${KERNEL_TAR} -C ${TMP_PATH}
    fi
  
    pushd ${TMP_PATH}/${KERNEL_NAME} > /dev/null || exit 1
  fi
  
  # Patching kernel with grsecurity
  if [ -n "${GRSEC_PATCH}" ]; then
    ${PATCH} -p1 < ${GRSEC_PATCH}
    
    # Configuring kernel with Grsecurity
    # Grsecurity configuration options 
    # cf. https://en.wikibooks.org/wiki/Grsecurity/Appendix/Grsecurity_and_PaX_Configuration_Options
    ${MAKE} ${ALT}
  
    # Update KERNEL_VERSION 
    KERNEL_VERSION=${KERNEL_VERSION}-grsec
  elif [ -n "${ALT}" ]; then
    # Configuring kernel
    ${MAKE} ${ALT}
  fi
  
  # Define install folder
  if [ -n "${DEB}" ]; then
    INSTALL_PATH=${TMP_PATH}/kernel-${KERNEL_VERSION}
  else
    INSTALL_PATH=${DEST_PATH}
  fi
  
  # Define and create output directory
  export KBUILD_OUTPUT=${TMP_PATH}/kernel-build-${KERNEL_VERSION}
  ${MKDIR} -p ${KBUILD_OUTPUT}
    
  # Copy config file
  ${CP} ${KERNEL_CONF} ${KBUILD_OUTPUT}/.config
    
  # Build and install kernel
  ${MKDIR} -p ${INSTALL_PATH}/boot
  ${MAKE} --jobs=$((NB_CORES+1)) --load-average=${NB_CORES}
  ${MAKE} INSTALL_PATH=${INSTALL_PATH}/boot install
  
  # Build and install kernel modules
  ${MAKE} --jobs=$((NB_CORES+1)) --load-average=${NB_CORES} modules
  ${MAKE} INSTALL_MOD_PATH=${INSTALL_PATH} modules_install
  
  # Install firmware
  ${MAKE} INSTALL_MOD_PATH=${INSTALL_PATH} firmware_install
  
  popd > /dev/null
  
  # Replace symbolic link
  ${RM} ${INSTALL_PATH}/lib/modules/${KERNEL_VERSION}/build
  ${RM} ${INSTALL_PATH}/lib/modules/${KERNEL_VERSION}/source
  
  # Create Debian package 
  if [ -n "${DEB}" ]; then
    ${MKDIR} -p kernel-${KERNEL_VERSION}/DEBIAN
      
    ${CAT} > kernel-${KERNEL_VERSION}/DEBIAN/control << EOF
Package: kernel
Version: ${KERNEL_VERSION}
Section: kernel
Priority: optional
Essential: no
Architecture: amd64
Maintainer: David DIALLO
Provides: linux-image
Description: Linux kernel, version ${KERNEL_VERSION}
This package contains the Linux kernel, modules and corresponding other
files, version: ${KERNEL_VERSION}
EOF
      
    ${CAT} > kernel-${KERNEL_VERSION}/DEBIAN/postinst << EOF
rm -f /boot/initrd.img-${KERNEL_VERSION}
update-initramfs -c -k ${KERNEL_VERSION}
EOF
      
    ${CAT} > kernel-${KERNEL_VERSION}/DEBIAN/postrm << EOF
rm -f /boot/initrd.img-${KERNEL_VERSION}
EOF
     
    ${CAT} > kernel-${KERNEL_VERSION}/DEBIAN/triggers << EOF
interest update-initramfs
EOF
      
    ${CHMOD} 755 kernel-${KERNEL_VERSION}/DEBIAN/postinst kernel-${KERNEL_VERSION}/DEBIAN/postrm
      
    ${FAKEROOT} ${DPKG_DEB} --build kernel-${KERNEL_VERSION}
      
    # Copy Debian package 
    ${CP} kernel-${KERNEL_VERSION}.deb ${DEST_PATH}
  
    # Delete Debian package and install folder
    if [ -z "${NO_DELETE}" ]; then
      ${RM} kernel-${KERNEL_VERSION}.deb
      ${RM} -rf kernel-${KERNEL_VERSION}
    fi
  fi
  
  # Delete temporary files
  if [ -z "${NO_DELETE}" ]; then
    # Delete kernel archive and decompressed kernel archive
    if [ -n "${GIT_PATH}" ]; then
      ${RM} ${KERNEL_TAR}
      ${RM} ${KERNEL_TAR}.sign
    fi
  
    ${RM} -rf ${KERNEL_NAME}
    ${RM} -rf ${KBUILD_OUTPUT}
  fi
  
  popd > /dev/null
}

build_system () {
  # Add Grub, Grub2 and locale packages
  INCLUDE=${INCLUDE},grub-common,grub2,grub2-common,systemd,systemd-sysv,initramfs-tools,isc-dhcp-client,locales
  
  if [ -n "${PART}" ]; then
    # Set partition number and reset FSTAB
    id=1
    unset FSTAB
  
    # Get partition informations
    for part in "${PART[@]}"; do
      IFS=$' \t' read name mount size type options dump pass <<< "${part}"
    
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
      ${MKE2FS} -F -t ${type} -L ${name} ${DEVICE}${id} 
  
      # Get UUID
      uuid=$(${BLKID} ${DEVICE}${id})
      uuid=${uuid#*UUID=\"}
      uuid=${uuid%%\"*}
  
      # Fill filesystem table FSTAB
      if [ "${name}" == "root" ]; then
        FSTAB=("${DEVICE}${id} ${mount} ${type} ${options} ${dump} ${pass} ${uuid}" "${FSTAB[@]}")
      elif [ "${name}" != "swap" ]; then 
        FSTAB=("${FSTAB[@]}" "${DEVICE}${id} ${mount} ${type} ${options} ${dump} ${pass} ${uuid}")
      fi
  
      # Manage Volume Group (LVM)
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
          IFS=$' \t' read name mount size type options dump pass <<< "${lvname}"
          if [ "${name}" != "boot" ]; then
            ${LVCREATE} -n ${name} -L ${size} ${VGNAME}
            if [ "${name}" == "swap" ]; then
              ${MKSWAP} -L ${name} /dev/mapper/${VGNAME}-${name}
            else
              ${MKE2FS} -F -t ${type} -L ${name} /dev/mapper/${VGNAME}-${name}; 
              
              # Fill filesystem table FSTAB
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
    IFS=$' \t' read device mount type options dump pass uuid <<< "${fstab}"
  
    ${MKDIR} -p ${DEST_PATH}${mount}
    ${MOUNT} ${device} ${DEST_PATH}${mount}
  done
  
  # Install Debian base system
  if [ -n "${EXCLUDE}" ]; then
    ${FAKECHROOT} fakeroot ${DEBOOTSTRAP} --arch=${ARCH} --include=${INCLUDE} --exclude=${EXCLUDE} --variant=${VARIANT} ${SUITE} ${DEST_PATH} ${MIRROR}
  else
    ${FAKECHROOT} fakeroot ${DEBOOTSTRAP} --arch=${ARCH} --include=${INCLUDE} --variant=${VARIANT} ${SUITE} ${DEST_PATH} ${MIRROR}
  fi
  
  # Remplace symbolic link
  IFS=$'\n'
  LINKS=$(${FIND} ${DEST_PATH} -type l -lname "${DEST_PATH}*" -printf "%l\t%p\n")
  for link in ${LINKS}; do
    IFS=$' \t' read path name <<< "$link"
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
  
  # Set basic configuration for an IPv4 DHCP
  ${CAT} > ${DEST_PATH}/etc/systemd/network/wired.network << EOF
[Match]
Name=en*

[Network]
DHCP=ipv4
EOF
  
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
    unset uuid
    IFS=$' \t' read device mount type options dump pass uuid <<< "${fstab}"
  
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
  ${CAT} > ${DEST_PATH}/chroot.sh << EOF
#!/bin/bash
# Install Grub
${GRUB_INSTALL} ${DEVICE}
${GRUB_MKCONFIG} -o /boot/grub/grub.cfg

# Configure locale
${SED} -i "s/^# fr_FR/fr_FR/" /etc/locale.gen
${LOCALE_GEN}
${LOCALE_UPDATE} LANG=fr_FR.UTF-8

# Configure timezone
${ECHO} "Europe/Paris" > /etc/timezone    
${DPKG_RECONFIGURE} --frontend=noninteractive tzdata

# Create a password for root
${ECHO} root:${ROOT_PASSWD} | ${CHPASSWD}

# Enable systemd-networkd.service
${SYSTEMCTL} enable systemd-networkd

# Quit the chroot environment
exit
EOF
  ${CHMOD} +x ${DEST_PATH}/chroot.sh
  
  # Entering the chroot environment
  ${CHROOT} ${DEST_PATH} ./chroot.sh 
  
  # Remove "chroot" script
  ${RM} ${DEST_PATH}/chroot.sh
  
  # Unbinding the virtual filesystems
  ${UMOUNT} ${DEST_PATH}/{dev,proc,sys}
  
  # Umount all partitions
  for (( index=${#FSTAB[@]}-1 ; index>=0 ; index-- )) ; do
    IFS=$' \t' read device mount type options dump pass uuid <<< "${FSTAB[index]}"
  
    ${UMOUNT} ${DEST_PATH}${mount}
  done
  
  # Deactivate Volume Group (LVM)
  if [ -n "${VGNAME}" ]; then
    ${VGCHANGE} -a n ${VGNAME}
  fi
}

# Main function
# Manage options 
for i in "$@"; do
  case ${i} in
    -a==*|--alt=*)
      j="${i#*=}"
      shift
        case $j in
          alldefconfig|allnoconfig|config|defconfig|menuconfig|oldconfig)
            ALT=${j}
            ;;
  
          *)    # unknown alternative configuration
            ${ECHO} -e ${USAGE}
            exit 1
            ;;
        esac
      ;;

    -d|--deb)
      DEB=1
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

    -g=*|--grsec=*)
      GRSEC_PATCH="${i#*=}"
      shift
      ;;

    -h|--help)
      ${ECHO} -e ${USAGE}
      exit 0
      ;;

    -i=*|--git=*)
      GIT_PATCH="${i#*=}"
      shift
      ;;

    -l=*|--local=*)
      KERNEL_PATH="${i#*=}"
      shift
      ;;

    -n|--nodelete)
      NO_DELETE=1
      ;;

    -p=*|--path=*)
      DEST_PATH="${i#*=}"
      shift
      ;;

    -s=*|--suite=*)
      SUITE="${i#*=}"
      shift
      ;;

    -t=*|--target=*)
      TARGET="${i#*=}"
      shift
      ;;

    -t=*|--temp=*)
      TMP_PATH="${i#*=}"
      shift
      ;;

    -v=*|--version=*)
      KERNEL_VERSION="${i#*=}"
      shift
      ;;

    -*|--*) # unknown option
      ${ECHO} -e ${USAGE}
      exit 1
      ;;
  
  esac
done

if [ $# -eq  4 ] && ([ "${1}" == "build" ] || [ "${1}" == "update" ]); then
  COMMAND=${1}
  DEVICE=${2}
  KERNEL_CONF=${3}
  KERNEL_VERSION=${4}
else
  ${ECHO} -e ${USAGE}
  exit 1
fi

# Assign default value in case of no option
if [ -z "${KERNEL_CONF}" ]; then
  KERNEL_CONF=.config
fi
if [ -z "${DEST_PATH}" ]; then
  DEST_PATH=byos
fi
if [ -z "${TMP_PATH}" ]; then
  if [ -d /tmp ]; then
    TMP_PATH=/tmp
  else
    ${ECHO} "Neither /tmp nor temporary folder exists" >&2
    exit 1
  fi
fi

# Convert relative path to absolute path
for i in DEST_PATH GRSEC_PATCH KERNEL_CONF KERNEL_PATH TMP_PATH; do 
  if [[ -n "${!i}" ]] && [[ ${!i} != /* ]]; then
    eval ${i}=`${PWD}`/${!i}
  fi
done

# Build system
if [ "${1}" == "build" ]; then
  # Assign default value in case of no option
  if [ -z "${SUITE}" ]; then
    SUITE=stable
  fi

  # Assign default value in case of no option
  if [ -z "${TARGET}" ]; then
    TARGET=debian
  fi

  # Build system
  #unset SYSTEM_OPTIONS
  #if [ -n "${FILE}" ]; then
  #  SYSTEM_OPTIONS="${SYSTEM_OPTIONS} -f=${FILE}"
  #fi
  #SYSTEM_OPTIONS="${SYSTEM_OPTIONS} -p=${DEST_PATH}"
  #${SYSTEM_BUILD} ${SYSTEM_OPTIONS} ${DEVICE} ${TARGET} ${SUITE}
  build_system
  
  # Check if build system succeeded
  if [ $? -ne 0 ]; then
    exit 1   
  fi
fi

# Mount rootfs partition
if [ -n "${VGNAME}" ]; then
  # Activate Volume Group (LVM)
  ${VGCHANGE} -a y ${VGNAME}

  ${MOUNT} /dev/mapper/${VGNAME}-root ${DEST_PATH}
else
  ${MOUNT} $(${BLKID} -L root) ${DEST_PATH}
fi

# Reset FSTAB
unset FSTAB

# Read fstab file and mount partitions
while read fstab; do
  case ${fstab} in
    \#*) 
      continue 
      ;;

    UUID=*)
      IFS=$' \t' read uuid mount type options dump pass <<< "${fstab}"
      device=$(${BLKID} -U ${uuid#UUID=})
      ;;

    /dev/*)
      IFS=$' \t' read device mount type options dump pass <<< "${fstab}"
      ;;

    *)
      continue 
      ;;

  esac

  # Fill filesystem table FSTAB
  if [[ ${mount} == / ]]; then
    FSTAB=("${device} ${mount} ${type} ${options} ${dump} ${pass}" "${FSTAB[@]}")
    continue
  elif [[ ${device} =~ ^/* ]]; then 
    FSTAB=("${FSTAB[@]}" "${device} ${mount} ${type} ${options} ${dump} ${pass}")
  fi

  # Mount all partitions
  ${MKDIR} -p ${DEST_PATH}${mount}
  ${MOUNT} ${device} ${DEST_PATH}${mount}
done < ${DEST_PATH}/etc/fstab

# Binding the virtual filesystems
${MOUNT} --bind /dev ${DEST_PATH}/dev
${MOUNT} -t proc none ${DEST_PATH}/proc
${MOUNT} -t sysfs none ${DEST_PATH}/sys

# Build or update Kernel
#unset KERNEL_OPTIONS
#if [ -n "${FILE}" ]; then
#  KERNEL_OPTIONS="${KERNEL_OPTIONS} -f=${FILE}"
#fi
#KERNEL_OPTIONS="${KERNEL_OPTIONS} -p=${DEST_PATH}"
#${KERNEL_BUILD} ${KERNEL_OPTIONS} ${KERNEL_CONF} ${KERNEL_VERSION}
build_kernel()

# Check if build kernel succeeded
if [ $? -ne 0 ]; then
  exit 1   
fi

# Create "chroot" script
${CAT} >> ${DEST_PATH}/chroot.sh << EOF
#!/bin/bash

# Delete previous RAM Disk
${RM} -f /boot/initrd.img-${KERNEL_VERSION}

# Create new RAM Disk
${UPDATE_INITRAMFS} -c -k ${KERNEL_VERSION}

# Update grub
${UPDATE_GRUB}

# Quit the chroot environment
exit
EOF
${CHMOD} +x ${DEST_PATH}/chroot.sh

# Entering the chroot environment
${CHROOT} ${DEST_PATH} ./chroot.sh 

# Remove "chroot" script
${RM} ${DEST_PATH}/chroot.sh

# Unbinding the virtual filesystems
${UMOUNT} ${DEST_PATH}/{dev,proc,sys}

# Umount all partitions
for (( index=${#FSTAB[@]}-1 ; index>=0 ; index-- )) ; do
  IFS=$' \t' read device mount type options dump pass <<< "${FSTAB[index]}"

  ${UMOUNT} ${DEST_PATH}${mount}
done

# Deactivate Volume Group (LVM)
if [ -n "${VGNAME}" ]; then
  ${VGCHANGE} -a n ${VGNAME}
fi

exit 0
