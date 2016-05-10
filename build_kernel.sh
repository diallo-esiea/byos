#!/bin/bash 

CAT=/bin/cat
CHMOD=/bin/chmod
CP=/bin/cp
ECHO=/bin/echo
LN=/bin/ln
MKDIR=/bin/mkdir
PRINTF=printf
PWD=/bin/pwd
RM=/bin/rm
SED=/bin/sed
TAR=/bin/tar

AWK=/usr/bin/awk
DPKG_DEB=/usr/bin/dpkg-deb
FAKEROOT=/usr/bin/fakeroot 
GPG=/usr/bin/gpg
MAKE=/usr/bin/make
PATCH=/usr/bin/patch
UNXZ=/usr/bin/unxz
WGET=/usr/bin/wget

NB_CORES=$(grep -c '^processor' /proc/cpuinfo)

USAGE="$(basename "$0") [options] {-c|--conf}=configuration-file {-v|--version}=kernel-version\n\n
\tparameters:\n
\t-----------\n
\t\t-c, --conf\tKernel configuration file\n
\t\t-v, --version\tKernel version to build\n\n
\toptions:\n
\t--------\n
\t\t-a, --alt\tAlternative Configuration (config, menuconfig, oldconfig, defconf, alldefconfig, allnoconfig,...)\n
\t\t-d, --deb\tCreate Debian package archive\n
\t\t-f, --file\tConfiguration file\n
\t\t-g, --grsec\tGrsecurity patch\n
\t\t-h, --help\tDisplay this message\n
\t\t-l, --local\tPath to get the kernel archive (instead of official Linux Kernel Archives URL)\n
\t\t-n, --nodelete\tKeep temporary files\n
\t\t-p, --path\tPath to install kernel and kernel modules (default=/boot and /lib)\n
\t\t-t, --temp\tTemporary folder"

for i in "$@"; do
  case $i in
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

    -c=*|--conf=*)
      CONF_FILE="${i#*=}"
      shift
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
        ${ECHO} "File $FILE does not exists"
        exit 1
      fi

      # Parse configuration file
      source ${FILE}

      break
      ;;

    -g=*|--grsec=*)
      GRSEC_PATCH="${i#*=}"
      shift
      ;;

    -h|--help)
      ${ECHO} -e ${USAGE}
      exit 0
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

    -t=*|--temp=*)
      TMP_PATH="${i#*=}"
      shift
      ;;

    -v=*|--version=*)
      KERNEL_VERSION="${i#*=}"
      shift
      ;;
  
    *)    # unknown option
      ${ECHO} -e ${USAGE}
      exit 1
      ;;
  
  esac
done

# Convert relative path to absolute path
for i in CONF_FILE DEST_PATH GRSEC_PATCH KERNEL_PATH TMP_PATH; do 
  if [[ -n "${!i}" ]] && [[ ${!i} != /* ]]; then
    eval $i=`${PWD}`/${!i}
  fi
done

# Check parameters
if [ -z "${CONF_FILE}" ]; then
  ${ECHO} "None configuration file" >&2
  exit 1
fi

if [ -z "${KERNEL_VERSION}" ]; then
  ${ECHO} "None kernel version" >&2
  exit 1
fi

# Assign default value in case of no option
if [ -z "${DEST_PATH}" ]; then
  DEST_PATH=/
else
  # Create DEST_PATH if not exists 
  ${MKDIR} -p ${DEST_PATH}
fi

if [ -z "${TMP_PATH}" ]; then
  if [ -d /tmp ]; then
    TMP_PATH=/tmp
  else
    ${ECHO} "Neither /tmp nor temporary folder exists" >&2
    exit 1
  fi
fi

pushd ${TMP_PATH} > /dev/null || exit 1

# kernel.org branch url and target files
KERNEL_NAME=linux-${KERNEL_VERSION}
KERNEL_TAR=${KERNEL_NAME}.tar

# Kernel archive and signature
if [ -z "${KERNEL_PATH}" ]; then
  KERNEL_URL=https://www.kernel.org/pub/linux/kernel/v${KERNEL_VERSION/%.*/.x}
  
  # Check if BOTH kernel version AND signature file exist
  ${WGET} -c --spider ${KERNEL_URL}/${KERNEL_TAR}.{sign,xz}
  
  if [ $? -ne 0 ]; then
    ${ECHO} "Kernel version does not exist" >&2
    exit 1
  fi
  
  # Download kernel AND signature
  ${WGET} -c ${KERNEL_URL}/${KERNEL_TAR}.{sign,xz}
else
  # Check if BOTH kernel version AND signature file exist
  if [ ! -f ${KERNEL_PATH}/${KERNEL_TAR}.xz ] || [ ! -f ${KERNEL_PATH}/${KERNEL_TAR}.sign ]; then
    ${ECHO} "Kernel version does not exist" >&2
    exit 1
  fi

  # Copy kernel AND signature
  ${CP} ${KERNEL_PATH}/${KERNEL_TAR}.{sign,xz} .
fi

# Initialize GPG keyrings
${PRINTF} "" | ${GPG}

# Uncompressing kernel archive
${UNXZ} ${KERNEL_TAR}.xz

# Download GPG keys
GPG_KEY=`${GPG} --verify ${KERNEL_TAR}.sign 2>&1 | ${AWK} '{print $NF}' | ${SED} -n '/[0-9]$/p' | ${SED} -n '1p'`
${GPG} --recv-keys ${GPG_KEY}

# Verify kernel archive against signature file
${GPG} --verify ${KERNEL_TAR}.sign

# Decompress kernel archive
${TAR} -xf ${KERNEL_TAR} -C ${TMP_PATH}

# Copy config file
${CP} ${CONF_FILE} ${KERNEL_NAME}/.config

pushd ${TMP_PATH}/${KERNEL_NAME} > /dev/null || exit 1

# Configuring kernel
if [ -n "${ALT}" ]; then
  ${MAKE} ${ALT}
fi

# Patching kernel with grsecurity
if [ -n "${GRSEC_PATCH}" ]; then

  ${PATCH} -p1 < ${GRSEC_PATCH}
  
  # Configuring kernel with Grsecurity
  # Grsecurity configuration options 
  # cf. https://en.wikibooks.org/wiki/Grsecurity/Appendix/Grsecurity_and_PaX_Configuration_Options
  ${MAKE}

  # Update KERNEL_VERSION 
  KERNEL_VERSION=${KERNEL_VERSION}-grsec
fi

# Define install folder
if [ -n "${DEB}" ]; then
  INSTALL_PATH=${TMP_PATH}/kernel-${KERNEL_VERSION}
else
  INSTALL_PATH=${DEST_PATH}
fi

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
${LN} -sf /usr/src/${KERNEL_NAME} ${INSTALL_PATH}/lib/modules/${KERNEL_VERSION}/build
${LN} -sf /usr/src/${KERNEL_NAME} ${INSTALL_PATH}/lib/modules/${KERNEL_VERSION}/source

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
  ${RM} ${KERNEL_TAR}
  ${RM} ${KERNEL_TAR}.sign
  ${RM} -rf ${KERNEL_NAME}
fi

popd > /dev/null

exit 0
