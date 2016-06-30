#!/bin/bash -xv

CAT=/bin/cat
CP=/bin/cp
CHMOD=/bin/chmod
ECHO=/bin/echo
MKDIR=/bin/mkdir
MOUNT=/bin/mount
PWD=/bin/pwd
RM=/bin/rm
UMOUNT=/bin/umount

BLKID=/sbin/blkid
VGCHANGE=/sbin/vgchange

CHROOT=/usr/sbin/chroot
UPDATE_GRUB=/usr/sbin/update-grub
UPDATE_INITRAMFS=/usr/sbin/update-initramfs

USAGE="$(basename "${0}") [options] DEVICE\n
\t\tDEVICE\tTarget device name\n
\toptions:\n
\t--------\n
\t\t-f=FILE, --file=FILE\tConfiguration file\n
\t\t-p=PATH, --path=PATH\tPath to install system (default=/mnt)\n"

# Manage options 
for i in "$@"; do
  case ${i} in
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

    -p=*|--path=*)
      DEST_PATH="${i#*=}"
      shift
      ;;

    -*|--*) # unknown option
      ${ECHO} -e ${USAGE}
      exit 1
      ;;
  
  esac
done

if [ $# -eq 1 ]; then
  DEVICE=${1}
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

# Build system
./build_system.sh -f=${FILE} -p=${DEST_PATH} ${DEVICE} ${TARGET} ${SUITE}

# Check if build system succeeded
if [ $? -ne 0 ]; then
  exit 1   
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

# Build Kernel
./build_kernel.sh -f=${FILE} -p=${DEST_PATH} ${KERNEL_CONF} ${KERNEL_VERSION}

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
