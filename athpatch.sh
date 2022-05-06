#!/bin/bash

function setArgs {
  unset optApply

  while [ $# -gt 0 ]
  do
    case "$1" in
      "-k"|"--kversion")
        shift
        KVERSION="$1"
        shift
        ;;
      "--hot"|"--hotapply")
        optApply=1
        shift
        ;;
      "--reboot")
        optApply=2
        shift
        ;;
      "--install"|"--installonly")
        optApply=3
        shift
        ;;
      "--compile"|"--compileonly")
        optApply=4
        shift
        ;;
      "-h"|"--help")
        shift
        printHelp
        ;;
      *)
        echo "Unrecognized input: $1"
        exit 1
        ;;
    esac
  done

  ARCH=$(uname -i)
  [ -z "$KVERSION" ] && KVERSION=$(basename -s ".${ARCH}" $(uname -r))
}

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
    unset dlCmd
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
          echo "Unrecognized input ${inDL}."
          unset inDL
          unset dlCmd
          ;;
      esac
      [ "$dlCmd" ] && eval "$dlCmd"
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
  cp /usr/lib/modules/${KVERSION}.${ARCH}/build/Module.symvers ./
  cp ~/rpmbuild/SOURCES/kernel-${ARCH}.config ./.config
  make oldconfig && make prepare
  make scripts
  make M=drivers/net/wireless/ath
}

function installDriver {
  echo "Installing driver"
  xz drivers/net/wireless/ath/ath.ko 
  cp -f /lib/modules/${KVERSION}.${ARCH}/kernel/drivers/net/wireless/ath/ath.ko.xz ~/kernelpatch/kernel-${KVERSION}.${ARCH}-${now}-ath.ko.xz.orig
  cp -f drivers/net/wireless/ath/ath.ko.xz ~/kernelpatch/kernel-${KVERSION}.${ARCH}-${now}-ath.ko.xz.patched
  sudo cp -f drivers/net/wireless/ath/ath.ko.xz /lib/modules/${KVERSION}.${ARCH}/kernel/drivers/net/wireless/ath/ath.ko.xz
  sudo depmod -a ${KVERSION}.${ARCH}
}

function applyChanges {
  echo "Applying changes"
  while [ -z "$optApply" ]; do
    echo "Please choose an option number:"
    echo "1) Attempt hot-apply of new driver (Default)"
    echo "2) Reboot"
    echo "3) Install driver and exit"
    echo "4) Don't apply, just exit"
    read optApply
    [ -z "optApply" ] && optApply=1
    if [[ ! "$optApply" =~ [1234] ]]; then
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
       installDriver
       ;;
    "4")
       echo "Exiting without applying. Your driver is located at $(pwd)/drivers/net/wireless/ath/ath.ko"
       echo "To manually install it run:"
       echo "xz $(pwd)/drivers/net/wireless/ath/ath.ko"
       echo "sudo cp -f $(pwd)/drivers/net/wireless/ath/ath.ko.xz /lib/modules/${KVERSION}.${ARCH}/kernel/drivers/net/wireless/ath/ath.ko.xz"
       echo "sudo depmod -a ${KVERSION}.${ARCH}"
       echo "Then reboot or reload the 'ath' kernel module manually"
       exit 0
       ;;
    *)
       echo "Option not recognized"
       ;;
  esac
}

function printHelp {
  cat << EOS
Installs a patch for the ath10k driver to allow use of 5GHz bands
in world regulatory domains

Usage: athpatch.sh
       athpatch.sh [-h|--help]
       athpatch.sh [-k|--kversion] [--hotapply|--reboot|--install|--compile]

  Running the utility with no options will launch a question and answer system

  -h
  --help
                Shows this help and exit
  -k
  --kversion
                Specify the kernel version to patch (and optionally download)
                The default is the currently running kernel version if this
                option is not specified
  --hotapply
  --reboot
  --install
  --compile
                Specify the application method
                --hotapply:
                    Attempt to apply the patch to the running kernel by removing
                    the current ath10k driver and installing the patched version
                    with minimal disruption
                --reboot
                    Automatically reboot the system after patched driver is installed
                    Be careful, the reboot happens immediately after the install
                --install
                    Install the patched driver into the specified kernel's directory
                    It will be initialized at next boot of that kernel
                --compile:
                    Only compile the driver and don't apply it at all
EOS

  exit 0
}

setArgs "$@"
runPatch
applyChanges
