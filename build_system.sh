#!/bin/bash -xv

CAT=/bin/cat
ECHO=/bin/echo
MKDIR=/bin/mkdir
MOUNT=/bin/mount
UMOUNT=/bin/umount

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
SUITE=sid           # jessie, wheezy, sid, stable, testing, unstable
# Attention le fakeroot ne fonctionne pas avec Jessie le 18/04/2016 (cf. https://github.com/dex4er/fakechroot/pull/37)
# => pour Jessie, remplacer FAKEROOT=<chaine vide> et FAKECHROOT=<chaine vide> et lancer build_system en root ou sudo
TARGET=debian
VARIANT=minbase     # minbase, buildd, fakechroot, scratchbox

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

# Entering the chroot environment
${FAKECHROOT} ${CHROOT} ${TARGET} /bin/bash 

# Configure locale
#${DPKG_RECONFIGURE} locales

# Create a password for root
#${PASSWD}

# Update Debian package database:
#${APT_GET} update

# Quit the chroot environment
#${EXIT}

# Binding the virtual filesystems
#${MOUNT} -o bind /dev ${TARGET}/dev
#${MOUNT} -o bind /sys ${TARGET}/sys
#${MOUNT} -t proc none ${TARGET}/proc

# Unbinding the virtual filesystems
#${UMOUNT} ${TARGET}/dev
#${UMOUNT} ${TARGET}/sys
#${UMOUNT} ${TARGET}/proc

exit 0
