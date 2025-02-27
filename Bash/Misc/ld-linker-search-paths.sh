#!/usr/bin/env bash

clear

if [ "${EUID}" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script with root/sudo permissions.'
    exit 1
fi

cat > '/etc/ld.so.conf.d/user-added.conf' <<'EOF'
/usr/local/x86_64-linux-gnu/lib
/usr/local/cuda/nvvm/lib64
/usr/local/cuda/targets/x86_64-linux/lib
/usr/local/lib64
/usr/local/x86_64-linux-gnu/lib/ldscripts
/usr/local/lib/x86_64-linux-gnu
/usr/local/lib
/usr/lib64
/usr/lib/x86_64-linux-gnu
/usr/lib
/lib64
/lib/x86_64-linux-gnu
/lib
EOF

sudo ldconfig
