#!/bin/bash

clear

list='/etc/apt/sources.list'

# make a backup of the file
if [ ! -f "$list.bak" ]; then
    cp -f "$list" "$list.bak"
fi

cat > "$list" <<EOF
###################################################
##
##  UBUNTU JAMMY
##
##  v22.04
##
##  /etc/apt/sources.list
##
##  ALL MIRRORS IN EACH CATAGORY ARE LISTED AS BEING
##  IN THE USA. IF YOU USE ALL THE LISTS YOU CAN RUN
##  INTO APT COMMAND ISSUES THAT STATE THERE ARE TOO
##  MANY FILES. JUST AN FYI FOR YOU.
##
###################################################
##                Default Mirrors                ##
##     Disabled due to slow download speeds      ##
##  The security updates have been left enabled  ##
###################################################
##
# deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
# deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
# deb http://archive.ubuntu.com/ubuntu/ jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
##
####################################################
##                                                ##
##                  20Gb Mirrors                  ##
##                                                ##
####################################################
##
## MAIN
##
deb deb https://mirror.enzu.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirror.genesisadaptive.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ jammy main restricted universe multiverse
deb http://mirror.pit.teraswitch.com/ubuntu/ jammy main restricted universe multiverse
##
## UPDATES
##
deb https://mirror.enzu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirror.genesisadaptive.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirror.pit.teraswitch.com/ubuntu/ jammy-updates main restricted universe multiverse
##
## BACKPORTS
##
deb https://mirror.enzu.com/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirror.genesisadaptive.com/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirror.pit.teraswitch.com/ubuntu/ jammy-backports main restricted universe multiverse
EOF

# OPEN AN EDITOR TO VIEW THE CHANGES
if which 'gedit' &>/dev/null; then
    gedit "$list"
elif which 'nano' &>/dev/null; then
    nano "$list"
elif which 'vi' &>/dev/null; then
    vi "$list"
else
    printf "\n%s\n\n" \
        "Could not find an EDITOR to open: $list"
    exit 1
fi
