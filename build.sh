#!/bin/bash -xv

ECHO=/bin/echo
PWD=/bin/pwd

BLKID=/sbin/blkid

USAGE="$(basename "${0}") [options]\n
\t\t-s=FILE, --fstab=FILE\tFSTAB output file\n"

# Manage options 
for i in "$@"; do
  case ${i} in
    -s=*|--fstab=*)
      FSTAB_FILE="${i#*=}"
      shift
      ;;

    -*|--*) # unknown option
      ${ECHO} -e ${USAGE}
      exit 1
      ;;
  
  esac
done

# Convert relative path to absolute path
for i in FSTAB_FILE; do 
  if [[ -n "${!i}" ]] && [[ ${!i} != /* ]]; then
    eval ${i}=`${PWD}`/${!i}
  fi
done

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
${ECHO} -e "device <${device}>\n";
done < ${FSTAB_FILE}
