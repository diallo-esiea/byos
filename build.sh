#!/bin/bash -xv

ECHO=/bin/echo
MKDIR=/bin/mkdir
MOUNT=/bin/mount
PWD=/bin/pwd
UMOUNT=/bin/umount

BLKID=/sbin/blkid

USAGE="$(basename "${0}") [options] DEVICE\n
\t\tDEVICE\tRoot device name\n
\toptions:\n
\t--------\n
\t\t-p=PATH, --path=PATH\tPath to install system (default=/mnt)\n"

# Manage options 
for i in "$@"; do
  case ${i} in
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

# Convert relative path to absolute path
for i in DEST_PATH; do 
  if [[ -n "${!i}" ]] && [[ ${!i} != /* ]]; then
    eval ${i}=`${PWD}`/${!i}
  fi
done

# Assign default value in case of no option
if [ -z "${DEST_PATH}" ]; then
  DEST_PATH=/mnt
else
  # Create DEST_PATH if not exists 
  ${MKDIR} -p ${DEST_PATH}
fi

# Mount rootfs  partition
${MOUNT} ${DEVICE} ${DEST_PATH}/

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

# Unbinding the virtual filesystems
${UMOUNT} ${DEST_PATH}/{dev,proc,sys}

# Umount all partitions
for (( index=${#FSTAB[@]}-1 ; index>=0 ; index-- )) ; do
  IFS=$' \t' read device mount type options dump pass <<< "${FSTAB[index]}"

  ${UMOUNT} ${DEST_PATH}${mount}
done

exit 0
