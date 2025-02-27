#!/usr/bin/env bash

clear

# CREATE VARIABLES
parent_dir="${PWD}"
tmp_dir="$(mktemp -d)"
scripts=('ffmpeg' 'ffpb' 'ffpb-loop' 'ffpb-loop-paths')

# CREATE AND CD INTO A RANDOM DIRECTORY
cd "${tmp_dir}" || exit 1

# DOWNLOAD THE SCRIPTS FROM GITHUB
wget -qN - -i 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/run-scripts/ffmpeg-scripts.txt'

# RENAME THE SCRIPTS
sudo mv 'convert-x265-cuda-ffmpeg.sh' 'ffmpeg'
sudo mv 'convert-x265-cuda-ffpb.sh' 'ffpb'
sudo mv 'convert-x265-cuda-ffpb-loop.sh' 'ffpb-loop'
sudo mv 'convert-x265-cuda-ffpb-loop-paths.sh' 'ffpb-loop-paths'

# MOVE THE SCRIPTS TO THE ORIGINAL DIRECTORY THE SCRIPT WAS EXECUTED FROM
sudo mv "${scripts[@]}" "${parent_dir}"

# CD BACK INTO THE ORIGINAL DIRECTORY
cd "${parent_dir}" || exit 1

# CHANGE THE FILE PERMISSIONS OF EACH SCRIPT
for script in "${scripts[@]}"
do
    sudo chown "${USER}":"${USER}" -R "${script}"
    sudo chmod a+rwx -R "${script}"
done

# DELETE THIS SCRIPT
if [ -f 'ffmpeg-scripts.sh' ]; then
    sudo rm 'ffmpeg-scripts.sh'
fi

# DELETE THE RANDOM DIRECTORY
sudo rm -fr "${tmp_dir}"
