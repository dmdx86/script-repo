#!/usr/bin/env bash

clear

fail_fn()
{
    printf "\n%s\n\n" "${1}"
    read -p 'Press enter to exit.'
}

installed() { return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

##
## Install Missing Gparted Packages
##

pkgs=(exfat-fuse exfatprogs f2fs-tools gparted hfsplus hfsprogs hfsutils jfsutils
      lvm2 nilfs-tools ntfs2btrfs ntfs-3g reiser4progs reiserfsprogs udftools xfsprogs)

for pkg in ${pkgs[@]}
do
    if ! installed "${pkg}"; then
        missing_pkgs+=" ${pkg}"
    fi
done

if [ -n "${missing_pkgs}" ]; then
    echo '$ Installing missing packages'
    echo
    for i in "${missing_pkgs}"
        do
            if ! sudo apt -y install ${i}; then
                fail_fn 'Failed to run APT package manager.'
            fi
        done
else
    echo '$ The packages are already installed.'
    echo
fi
