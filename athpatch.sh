#!/bin/bash

function hotApply {
  sudo rmmod ath10k_pci ath10k_core ath
  sudo modprobe ath10k_pci
}

function rebootSystem {
  read -p "Reboot now? [Y/n]: " RBT
  [[ -z "$RBT" ]] && RBT="y"
  [[ "$RBT" =~ ^[yY]$ ]] && sudo reboot
}

function runPatch {
  now=`date +%Y%m%d%H%M%S`
  echo "Checking for required build packages"
  declare -a pkgsMissing
  declare -a REQBUILDPKGS=( make gcc gcc-c++ tar patch kernel-devel bison flex elfutils-libelf-devel bc openssl-devel python3 crda )
  installedPkgs=$(rpm -qa)
  for pkg in ${REQBUILDPKGS[@]}; do
    if ! grep -q $pkg <<< "$installedPkgs"; then
      pkgsMissing+=( "$pkg" )
    fi
  done
  if [ ${#pkgsMissing[@]} -ne 0 ]; then
    echo "Required packages are missing: ${pkgsMissing[@]}"
    exit 1
  fi
  
  KVERSION=$(basename -s '.x86_64' $(uname -r))
  
  if [ -d ~/rpmbuild ]; then
    rm -rf ~/rpmbuild/
  fi
  echo "Setting up build environment"
  mkdir -p ~/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
  echo '%_topdir %(echo $HOME)/rpmbuild' > ~/.rpmmacros
  
  echo "Preparing source kernel"
  [ ! -d ~/kernel ] && mkdir ~/kernel
  cd ~/kernel
  while [ ! -f "./kernel-${KVERSION}.src.rpm" ]; do
    read -p "Download kernel source [Y/n]? " inDL
    [ -z "$inDL" ] && inDL='y'
    if [[ "$inDL" =~ [yY] ]]; then
      echo "Choose a download source number:"
      echo "1) DNF (Default)"
      echo "2) CentOS Vault"
      read inDL
      [ -z "$inDL" ] && inDL="1"
      case "$inDL" in
        "1")
            dlCmd="dnf download --source --downloaddir=./ kernel-${KVERSION}"
            ;;
        "2")
            echo 'Enter the URL OS release version from https://vault.centos.org/'
            read -p "i.e. 8.5.2111: " DLLINK
            dlCmd="curl -O https://vault.centos.org/${DLLINK}/BaseOS/Source/SPackages/kernel-${KVERSION}.src.rpm"
            ;;
        *)
          echo "Unrecognized input ${inDL}. Exiting"
          exit 1
          ;;
      esac
      eval "$dlCmd"
    else
      read -p "Place the file kernel-${KVERSION}.src.rpm in the directory $(pwd) and then press enter to continue" cont
    fi
  done
  
  echo "Installing source kernel"
  rpm -i kernel-${KVERSION}.src.rpm 2>&1 | grep -v exist
  cp ~/rpmbuild/SOURCES/linux-${KVERSION}.tar.xz ./
  tar -xJf linux-${KVERSION}.tar.xz 
  
  echo "Applying ath10k patches"
  patch -i ~/kernelpatch/regd.c.patch linux-${KVERSION}/drivers/net/wireless/ath/regd.c 
  [[ $? -ne 0 ]] && echo "could not patch regd.c" && exit 1
  patch -i ~/kernelpatch/Kconfig.patch linux-${KVERSION}/drivers/net/wireless/ath/Kconfig 
  [[ $? -ne 0 ]] && echo "could not patch Kconfig" && exit 1
  
  echo "Compiling driver"
  cd linux-${KVERSION}
  make clean && make mrproper
  make mrproper
  cp /usr/lib/modules/${KVERSION}.x86_64/build/Module.symvers ./
  cp /home/guy/rpmbuild/SOURCES/kernel-x86_64.config ./.config
  make oldconfig && make prepare
  make scripts
  make M=drivers/net/wireless/ath
}

function installDriver {
  echo "Installing driver"
  xz drivers/net/wireless/ath/ath.ko 
  cp -f /lib/modules/${KVERSION}.x86_64/kernel/drivers/net/wireless/ath/ath.ko.xz ~/kernelpatch/kernel-${KVERSION}-${now}-ath.ko.xz.bak
  sudo cp -f drivers/net/wireless/ath/ath.ko.xz /lib/modules/${KVERSION}.x86_64/kernel/drivers/net/wireless/ath/ath.ko.xz 
  sudo depmod -a
}

function applyChanges {
  echo "Applying changes"
  unset optApply
  while [ -z "$optApply" ]; do
    echo "Please choose an option number:"
    echo "1) Attempt hot-apply of new driver (Default)"
    echo "2) Reboot"
    echo "3) Don't apply, just exit"
    read optApply
    [ -z "optApply" ] && optApply=1
    if [[ ! "$optApply" =~ [123] ]]; then
      unset optApply
    fi
  done
  
  case "$optApply" in
    "1")
       installDriver
       hotApply
       ;;
    "2")
       installDriver
       rebootSystem
       ;;
    "3")
       echo "Exiting without applying. Your driver is located at $(pwd)/drivers/net/wireless/ath/ath.ko"
       echo "To manually install it run:"
       echo "xz $(pwd)/drivers/net/wireless/ath/ath.ko"
       echo "sudo cp -f $(pwd)/drivers/net/wireless/ath/ath.ko.xz /lib/modules/${KVERSION}.x86_64/kernel/drivers/net/wireless/ath/ath.ko.xz"
       echo "sudo depmod -a"
       echo "Then reboot or reload the 'ath' kernel module manually"
       exit 0
       ;;
    *)
       echo "Option not recognized"
       ;;
  esac
}

runPatch
applyChanges
