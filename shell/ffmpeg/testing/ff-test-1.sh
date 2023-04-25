#!/bin/bash
# shellcheck disable=SC2016,SC2034,SC2046,SC2066,SC2068,SC2086,SC2162,SC2317

#################################################################################
##
##  GitHub: https://github.com/slyfox1186/script-repo
##
##  Forked: https://github.com/markus-perl/ffmpeg-build-script/
##
##  Supported Distros: Debian-based ( Debian, Ubuntu, etc. )
##
##  Supported architecture: x86_x64
##
##  Purpose: Build FFmpeg from source code with addon development
##           libraries also compiled from source code to ensure the
##           latest in extra functionality
##
##  Cuda:    If the cuda libraries are not installed (for geforce cards only)
##           the user will be prompted by the script to install them so that
##           hardware acceleration is enabled when compiling FFmpeg
##
##  Updated: 04.13.23
##
##  Version: 3.3
##
#################################################################################

##
## define variables
##

# FFmpeg version: Whatever the latest Git pull from: https://git.ffmpeg.org/gitweb/ffmpeg.git
progname="${0:2}"
script_ver='3.3'
cuda_ver='12.1'
packages="$PWD"/packages
workspace="$PWD"/workspace
install_dir='/usr/bin'
CFLAGS="-I$workspace/include -I/usr/local"
LDFLAGS="-L$workspace"/lib
LDEXEFLAGS=''
EXTRALIBS='-ldl -lpthread -lm -lz'
cnf_ops=()
nonfree_and_gpl='false'
latest='false'

# create the output directories
mkdir -p "$packages"
mkdir -p "$workspace"

##
## set the available cpu thread and core count for parallel processing (speeds up the build process)
##

if [ -f '/proc/cpuinfo' ]; then
    cpu_threads="$(grep -c ^processor '/proc/cpuinfo')"
else
    cpu_threads="$(nproc --all)"
fi
cpu_cores="$(grep ^cpu\\scores '/proc/cpuinfo' | uniq | awk '{print $4}')"

##
## define functions
##

exit_fn()
{
    echo
    echo 'Make sure to star this repository to show your support!'
    echo
    echo 'https://github.com/slyfox1186/script-repo/'
    echo
    exit 0
}

fail_fn()
{
    echo
    echo 'Please create a support ticket'
    echo
    echo 'https://github.com/slyfox1186/script-repo/issues'
    echo
    exit 1
}

fail_pkg_fn()
{
    echo
    echo "The '$1' package is not installed. It is required for this script to run."
    echo
    exit 1
}

cleanup_fn()
{
    echo '=========================================='
    echo ' Do you want to clean up the build files? '
    echo '=========================================='
    echo
    echo '[1] Yes'
    echo '[2] No'
    echo
    read -p 'Your choices are (1 or 2): ' cleanup_ans

    if [[ "${cleanup_ans}" -eq '1' ]]; then
        remove_dir "$packages"
        remove_dir "$workspace"
        remove_file "$0"
        echo 'cleanup finished.'
        exit_fn
    elif [[ "${cleanup_ans}" -eq '2' ]]; then
        exit_fn
    else
        echo 'Bad user input'
        echo
        read -p 'Press enter to try again.'
        echo
        cleanup_fn
    fi
}

ff_ver_fn()
{
    echo
    echo '===================================='
    echo '       FFmpeg Build Complete        '
    echo '===================================='
    echo
    echo 'The binary files can be found in the following locations'
    echo
    echo "ffmpeg:  $install_dir/ffmpeg"
    echo "ffprobe: $install_dir/ffprobe"
    echo "ffplay:  $install_dir/ffplay"
    echo
    echo '============================'
    echo '       FFmpeg Version       '
    echo '============================'
    echo
    ffmpeg -version
    echo
    cleanup_fn
}

make_dir()
{
    remove_dir "$1"
    if ! mkdir "$1"; then
        printf "\n Failed to create dir %s" "$1"
        echo
        exit 1
    fi
}

remove_file()
{
    if [ -f "$1" ]; then
        rm -f "$1"
    fi
}

remove_dir()
{
    if [ -d "$1" ]; then
        rm -fr "$1"
    fi
}

download()
{
    dl_path="$packages"
    dl_file="${2:-"${1##*/}"}"

    if [[ "$dl_file" =~ tar. ]]; then
        target_dir="${dl_file%.*}"
        target_dir="${3:-"${target_dir%.*}"}"
    else
        target_dir="${3:-"${dl_file%.*}"}"
    fi

    if [ -f "$dl_path/$dl_file" ]; then
        sudo chown $USER:$USER "$dl_path/$dl_file"
    fi

    if [ ! -f "$dl_path/$dl_file" ]; then
        echo "Downloading $1 as $dl_file"
        if ! curl -Lso "$dl_path/$dl_file" "$1"; then
            echo
            echo "The script failed to download \"$1\" and will try again in 10 seconds"
            sleep 10
            echo
            if ! curl -Lso "$dl_path/$dl_file" "$1"; then
                echo
                echo "The script failed to download \"$1\" two times and will exit the build"
                echo
                fail_fn
            fi
        fi
        echo 'Download Completed'
        echo
    else
        echo "$dl_file is already downloaded"
    fi

    make_dir "$dl_path/$target_dir"

    if [ -n "$3" ]; then
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" 2>/dev/null >/dev/null; then
            fail_fn "Failed to extract $dl_file"
        fi
    else
        if ! tar -xf "$dl_path/$dl_file" -C "$dl_path/$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            fail_fn "Failed to extract $dl_file"
        fi
    fi

    echo "File extracted: $dl_file"

    cd "$dl_path/$target_dir" || fail_fn "Unable to change the working directory to $target_dir"
}

download_git()
{
    dl_path="$packages"
    dl_url="$1"
    dl_file="$2"
    dl_args="$3"
    target_dir="$dl_path/$dl_file"

    if [ -n "$dl_args" ]; then
        git_cmd "$dl_url $dl_args" "$target_dir"
        return 0
    fi

    # first download attempt
    if [ -d "$target_dir" ]; then
        sudo rm -fr "$target_dir"
    else
        echo "Downloading $dl_file"
        if ! git clone -q "$dl_url" "$target_dir"; then
            echo
            echo "The script failed to download \"$dl_file\" and will try again in 10 seconds"
            sleep 10
            echo
            if ! git clone -q "$dl_url" "$target_dir"; then
                fail_fn "The script failed to download \"$dl_file\" two times and will exit the build"
            fi
        fi
        echo 'Download Complete'
        echo
    fi
 
    cd "$target_dir" || fail_fn "Unable to change the working directory to $target_dir"
}

# create txt files to check versions
ver_file_tmp="$workspace/latest-versions-tmp.txt"
ver_file="$workspace/latest-versions.txt"

if [ ! -f "$ver_file_tmp" ]; then
    touch "$ver_file_tmp"
fi
if [ ! -f "$ver_file" ]; then
    touch "$ver_file"
fi

# PULL THE LATEST VERSIONS OF EACH PACKAGE FROM THE WEBSITE API
curl_timeout='5'

git_1_fn()
{
    local github_repo github_url github_repo_name

    # SCRAPE GITHUB WEBSITE FOR LATEST REPO VERSION
    github_repo="$1"
    github_url="$2"
    github_repo_name="$(echo $github_repo | sed -e 's|.*/||')"

    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://api.github.com/repos/$github_repo/$github_url")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver="${g_ver#v}"
        g_ssl="${g_ver#OpenSSL }"
        g_pkg="${g_ver#pkg-config-}"
        g_url="$(echo "$curl_cmd" | jq -r '.[0].tarball_url')"
    fi

    if [ -n "$g_pkg" ]; then
        g_ver="$g_pkg"
    fi
    if [ -n "$g_ssl" ]; then
        g_ver="$g_ssl"
    fi

    echo "$github_repo_name-$g_ver" >> "$ver_file_tmp"
    awk '!NF || !seen[$0]++' "$latest_txt_tmp" > "$ver_file"
}

git_2_fn()
{
    videolan_repo="$1"
    videolan_url="$2"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://code.videolan.org/api/v4/projects/$videolan_repo/repository/$videolan_url")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].commit.id')"
        g_sver="$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')"
        g_ver1="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver1="${g_ver1#v}"
    fi
}

git_3_fn()
{
    gitlab_repo="$1"
    gitlab_url="$2"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://gitlab.com/api/v4/projects/$gitlab_repo/repository/$gitlab_url")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver="${g_ver#v}"

        g_ver1="$(echo "$curl_cmd" | jq -r '.[0].commit.id')"
        g_ver1="${g_ver1#v}"
        g_sver1="$(echo "$curl_cmd" | jq -r '.[0].commit.short_id')"

        g_ver2="$(echo "$curl_cmd" | jq -r '.[3].commit.id')"
        g_ver2="${g_ver2#v}"
        g_sver2="$(echo "$curl_cmd" | jq -r '.[3].commit.short_id')"
    fi
}

git_4_fn()
{
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://gitlab.freedesktop.org/api/v4/projects/$gitlab_repo/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
    fi
}

git_5_fn()
{
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL 'https://bitbucket.org/!api/2.0/repositories/multicoreware/x265_git/effective-branching-model')"; then
        g_ver="$(echo "$curl_cmd" | jq '.development.branch.target' | grep -Eo '[0-9a-z][0-9a-z]+' | sort | head -n 1)"
        g_sver="${g_ver::7}"
    fi
}

git_6_fn()
{
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://gitlab.gnome.org/api/v4/projects/$gitlab_repo/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver="${g_ver#v}"
    fi
}

git_7_fn()
{
    gitlab_repo="$1"
    if curl_cmd="$(curl -m "$curl_timeout" -sSL "https://git.archive.org/api/v4/projects/$gitlab_repo/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
        g_ver="${g_ver#v}"
    fi
}

git_ver_fn()
{
    local v_flag v_tag url_tag

    v_url="$1"
    v_tag="$2"

    if [ -n "$3" ]; then
        v_flag="$3"
    fi

    if [ "$v_flag" = 'B' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn' gv_url='branches'
    elif [ "$v_flag" = 'B' ] && [  "$v_tag" = '3' ]; then
        url_tag='git_3_fn' gv_url='branches'
    fi

    if [ "$v_flag" = 'X' ] && [  "$v_tag" = '5' ]; then
        url_tag='git_5_fn'
    fi

    if [ "$v_flag" = 'T' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn' gv_url='tags'
    elif [ "$v_flag" = 'T' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn' gv_url='tags'
    elif [ "$v_flag" = 'T' ] && [  "$v_tag" = '3' ]; then
        url_tag='git_3_fn' gv_url='tags'
    fi

    if [ "$v_flag" = 'R' ] && [  "$v_tag" = '1' ]; then
        url_tag='git_1_fn'; gv_url='releases'
    elif [ "$v_flag" = 'R' ] && [  "$v_tag" = '2' ]; then
        url_tag='git_2_fn'; gv_url='releases'
    elif [ "$v_flag" = 'R' ] && [  "$v_tag" = '3' ]; then
        url_tag='git_3_fn' gv_url='releases'
    fi

    case "$v_tag" in
        1)          url_tag='git_1_fn';;
        2)          url_tag='git_2_fn';;
        3)          url_tag='git_3_fn';;
        4)          url_tag='git_4_fn';;
        5)          url_tag='git_5_fn';;
        6)          url_tag='git_6_fn';;
        7)          url_tag='git_7_fn';;
    esac

    "$url_tag" "$v_url" "$gv_url" 2>/dev/null
}

check_version()
{
    github_repo="$1"
    github_repo_name="$(echo $github_repo | sed -e 's|.*/||')"
    latest_txt_tmp="$ver_file_tmp"
    latest_txt="$ver_file"

    awk '!NF || !seen[$0]++' "$latest_txt_tmp" > "$latest_txt"
    check_ver="$(grep -Eo "$github_repo_name-[0-9\.]+" "$latest_txt" | sort | head -n1)"

        if [ -n "$check_ver" ]; then
            g_nocheck='0'
        else
            g_nocheck='1'
        fi
}

execute()
{
    echo "$ $*"

    if ! output=$("$@" 2>&1); then
        fail_fn "Failed to Execute $*"
    fi
}

build()
{
    echo
    echo "building $1 - version $2"
    echo '===================================='

    if [ -f "$packages/$1.done" ]; then
    if grep -Fx "$2" "$packages/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $packages/$1.done lockfile to rebuild it."
            return 1
        elif $latest; then
            echo "$1 is outdated and will be rebuilt using version $2"
            return 0
        else
            echo "$1 is outdated, but will not be rebuilt. Pass in --latest to rebuild it or remove $packages/$1.done lockfile."
            return 1
        fi
    fi

    return 0
}

command_exists()
{
    if ! [[ -x $(command -v "$1") ]]; then
        return 1
    fi

    return 0
}

library_exists()
{

    if ! [[ -x "$(pkg-config --exists --print-errors "$1" 2>&1 >/dev/null)" ]]; then
        return 1
    fi

    return 0
}

build_done() { echo "$2" > "$packages/$1.done"; }

installed() { return $(dpkg-query -W -f '${Status}\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

cuda_fail_fn()
{
    echo '======================================================'
    echo '                    Script error:'
    echo '======================================================'
    echo
    echo "Unable to locate directory: /usr/local/cuda-12.1/bin/"
    echo
    read -p 'Press enter to exit.'
    clear
    fail_fn
}

gpu_arch_fn()
{
    is_wsl="$( uname -a | grep -Eo 'WSL2')"

    if [ -n "$is_wsl" ]; then
        sudo apt -q -y install nvidia-utils-525
    fi

    gpu_name="$(nvidia-smi --query-gpu=gpu_name --format=csv | sort -r | head -n 1)"

    if [ "$gpu_name" = 'name' ]; then
        gpu_name="$(nvidia-smi --query-gpu=gpu_name --format=csv | sort | head -n 1)"
    fi

    case "$gpu_name" in
        'NVIDIA GeForce GT 1010')         gpu_type='1';;
        'NVIDIA GeForce GTX 1030')        gpu_type='1';;
        'NVIDIA GeForce GTX 1050')        gpu_type='1';;
        'NVIDIA GeForce GTX 1060')        gpu_type='1';;
        'NVIDIA GeForce GTX 1070')        gpu_type='1';;
        'NVIDIA GeForce GTX 1080')        gpu_type='1';;
        'NVIDIA TITAN Xp')                gpu_type='1';;
        'NVIDIA Tesla P40')               gpu_type='1';;
        'NVIDIA Tesla P4')                gpu_type='1';;
        'NVIDIA GeForce GTX 1180')        gpu_type='2';;
        'NVIDIA GeForce GTX Titan V')     gpu_type='2';;
        'NVIDIA Quadro GV100')            gpu_type='2';;
        'NVIDIA Tesla V100')              gpu_type='2';;
        'NVIDIA GeForce GTX 1660 Ti')     gpu_type='3';;
        'NVIDIA GeForce RTX 2060')        gpu_type='3';;
        'NVIDIA GeForce RTX 2070')        gpu_type='3';;
        'NVIDIA GeForce RTX 2080')        gpu_type='3';;
        'NVIDIA Quadro RTX 4000')         gpu_type='3';;
        'NVIDIA Quadro RTX 5000')         gpu_type='3';;
        'NVIDIA Quadro RTX 6000')         gpu_type='3';;
        'NVIDIA Quadro RTX 8000')         gpu_type='3';;
        'NVIDIA T1000')                   gpu_type='3';;
        'NVIDIA T2000')                   gpu_type='3';;
        'NVIDIA Tesla T4')                gpu_type='3';;
        'NVIDIA GeForce RTX 3050')        gpu_type='4';;
        'NVIDIA GeForce RTX 3060')        gpu_type='4';;
        'NVIDIA GeForce RTX 3070')        gpu_type='4';;
        'NVIDIA GeForce RTX 3080')        gpu_type='4';;
        'NVIDIA GeForce RTX 3080 Ti')     gpu_type='4';;
        'NVIDIA GeForce RTX 3090')        gpu_type='4';;
        'NVIDIA RTX A2000')               gpu_type='4';;
        'NVIDIA RTX A3000')               gpu_type='4';;
        'NVIDIA RTX A4000')               gpu_type='4';;
        'NVIDIA RTX A5000')               gpu_type='4';;
        'NVIDIA RTX A6000')               gpu_type='4';;
        'NVIDIA GeForce RTX 4080')        gpu_type='5';;
        'NVIDIA GeForce RTX 4090')        gpu_type='5';;
        'NVIDIA H100')                    gpu_type='6';;
    esac

    if [ -n "$gpu_type" ]; then
        case "$gpu_type" in
            1)        gpu_arch='compute_61,code=sm_61';;
            2)        gpu_arch='compute_70,code=sm_70';;
            3)        gpu_arch='compute_75,code=sm_75';;
            4)        gpu_arch='compute_86,code=sm_86';;
            5)        gpu_arch='compute_89,code=sm_89';;
            6)        gpu_arch='compute_90,code=sm_90';;
        esac
    fi
}

# PRINT THE OPTIONS AVAILABLE WHEN MANUALLY RUNNING THE SCRIPT
usage()
{
    echo "Usage: $progname [OPTIONS]"
    echo
    echo 'Options:'
    echo '    -h, --help                                         Display usage information'
    echo '            --version                                    Display version information'
    echo '    -b, --build                                        Starts the build process'
    echo '            --enable-gpl-and-non-free    Enable GPL and non-free codecs    - https://ffmpeg.org/legal.html'
    echo '    -c, --cleanup                                    Remove all working dirs'
    echo '            --latest                                     Build latest version of dependencies if newer available'
    echo '            --full-static                            Build a full static FFmpeg binary (eg. glibc, pthreads, etc...) **only Linux**'
    echo '                                                                 Note: Because of the NSS (Name Service Switch), glibc does not recommend static links.'
    echo
}

echo "ffmpeg-build-script v$script_ver"
echo '======================================'
echo

while (($# > 0)); do
    case $1 in
    -h | --help)
        usage
        exit 0
        ;;
    --version)
        echo "$script_ver"
        exit 0
        ;;
    -*)
        if [[ "$1" == '--build' || "$1" =~ '-b' ]]; then
            bflag='-b'
        fi
        if [[ "$1" == '--enable-gpl-and-non-free' ]]; then
            cnf_ops+=('--enable-nonfree')
            cnf_ops+=('--enable-gpl')
            nonfree_and_gpl='true'
        fi
        if [[ "$1" == '--cleanup' || "$1" =~ '-c' && ! "$1" =~ '--' ]]; then
            cflag='-c'
            cleanup_fn
        fi
        if [[ "$1" == '--full-static' ]]; then
            LDEXEFLAGS='-static'
        fi
        if [[ "$1" == '--latest' ]]; then
            latest='true'
        fi
        shift
        ;;
    *)
        usage
        echo
        fail_fn
        ;;
    esac
done

if [ -z "$bflag" ]; then
    if [ -z "$cflag" ]; then
        usage
    fi
    exit 0
fi

echo "The script will utilize $cpu_threads CPU cores for parallel processing to accelerate the build speed."
echo

if "$nonfree_and_gpl"; then
    echo 'The script has been configured to run with GPL and non-free codecs enabled'
    echo
fi

if [ -n "$LDEXEFLAGS" ]; then
    echo 'The script has been configured to run in full static mode.'
    echo
fi

# set global variables
JAVA_HOME='/usr/lib/jvm/java-17-openjdk-amd64'
export JAVA_HOME

# libbluray requries that this variable be set
PATH="\
$workspace/bin:\
$JAVA_HOME/bin:\
$PATH\
"
export PATH

# set the pkg-config path
PKG_CONFIG_PATH="\
$workspace/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/share/pkgconfig:\
/usr/lib64/pkgconfig\
"
export PKG_CONFIG_PATH

LD_LIBRARY_PATH="\
$workspace/include:\
/usr/include:\
/usr/local/include\
"
export LD_LIBRARY_PATH

if ! command_exists 'make'; then
    fail_pkg_fn 'make'
fi

if ! command_exists 'g++'; then
    fail_pkg_fn 'g++'
fi

if ! command_exists 'curl'; then
    fail_pkg_fn 'curl'
fi

if ! command_exists 'jq'; then
    fail_pkg_fn 'jq'
fi

if ! command_exists 'cargo'; then
    echo 'The '\''cargo'\'' command was not found.'
    echo
    echo 'The rav1e encoder will not be available.'
fi

if ! command_exists 'python3'; then
    echo 'The '\''python3'\'' command was not found.'
    echo
    echo 'The '\''Lv2'\'' filter and '\''dav1d'\'' decoder will not be available.'
fi

cuda_fn()
{
    printf "\n%s\n\n%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n\n" \
        'Pick your Linux distro from the list below:' \
        'Supported architecture: x86_x64' \
        '[1] Debian 10' \
        '[2] Debian 11' \
        '[3] Ubuntu 18.04' \
        '[4] Ubuntu 20.04' \
        '[5] Ubuntu 22.04' \
        '[6] Ubuntu Windows (WSL)' \
        '[7] Skip this'

    read -p 'Your choices are (1 to 7): ' c_dist

    case "$c_dist" in
        1)
            wget --show progress -cqO "cuda-12.1.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda-repo-debian10-12-1-local_12.1.0-530.30.02-1_amd64.deb'
            sudo dpkg -i "cuda-12.1.deb"
            sudo cp /var/cuda-repo-debian10-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            sudo add-apt-repository contrib
            ;;
        2)
            wget --show progress -cqO "cuda-12.1.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda-repo-debian11-12-1-local_12.1.0-530.30.02-1_amd64.deb'
            sudo dpkg -i "cuda-12.1.deb"
            sudo cp /var/cuda-repo-debian11-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            sudo add-apt-repository contrib
            ;;
        3)
            wget --show progress -cq 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/cuda-ubuntu1804.pin'
            sudo mv 'cuda-ubuntu1804.pin' '/etc/apt/preferences.d/cuda-repository-pin-600'
            wget --show progress -cqO "cuda-12.1.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda-repo-ubuntu1804-12-1-local_12.1.0-530.30.02-1_amd64.deb'
            sudo dpkg -i "cuda-12.1.deb"
            sudo cp /var/cuda-repo-ubuntu1804-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            ;;
        4)
            wget --show progress -cq 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-ubuntu2004.pin'
            sudo mv 'cuda-ubuntu2004.pin' '/etc/apt/preferences.d/cuda-repository-pin-600'
            wget --show progress -cqO "cuda-12.1.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda-repo-ubuntu2004-12-1-local_12.1.0-530.30.02-1_amd64.deb'
            sudo dpkg -i "cuda-12.1.deb"
            sudo cp /var/cuda-repo-ubuntu2004-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            ;;
        5)
            wget --show progress -cq 'https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin'
            sudo mv 'cuda-ubuntu2204.pin' '/etc/apt/preferences.d/cuda-repository-pin-600'
            wget --show progress -cqO "cuda-12.1.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda-repo-ubuntu2204-12-1-local_12.1.0-530.30.02-1_amd64.deb'
            sudo dpkg -i "cuda-12.1.deb"
            sudo cp /var/cuda-repo-ubuntu2204-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            ;;
        6)
            wget --show progress -cq 'https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin'
            sudo mv 'cuda-wsl-ubuntu.pin' '/etc/apt/preferences.d/cuda-repository-pin-600'
            wget --show progress -cqO "cuda-12.1.deb" 'https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda-repo-wsl-ubuntu-12-1-local_12.1.0-1_amd64.deb'
            sudo dpkg -i "cuda-12.1.deb"
            sudo cp /var/cuda-repo-wsl-ubuntu-12-1-local/cuda-*-keyring.gpg '/usr/share/keyrings/'
            ;;
        7)
            exit_fn
            ;;
        *)
            fail_fn 'Bad User Input. Run the script again.'
            ;;
    esac

    # UPDATE THE APT PACKAGES THEN INSTALL THE CUDA-SDK-TOOLKIT
    sudo apt update
    sudo apt -y install cuda

    # CHECK IF THE CUDA FOLDER EXISTS TO ENSURE IT WAS INSTALLED
    iscuda="$(sudo find /usr/local/ -type f -name nvcc)"
    cudaPATH="$(sudo find /usr/local/ -type f -name nvcc | grep -Eo '^.*\/bi[n]?')"

    if [ -z "$cudaPATH" ]; then
        cuda_fail_fn
    else
        PATH="$cudaPATH:$PATH"
        export PATH
    fi
}

##
## required build packages
##

build_pkgs_fn()
{
    echo
    echo 'Installing required development packages'
    echo '=========================================='

    pkgs=(ant build-essential cmake cmake-curses-gui flex flexc++ g++ gcc \
          gtk-doc-tools git-all help2man javacc jq junit libcairo2-dev \
          libcdio-paranoia-dev libcurl4-gnutls-dev libglib2.0-dev \
          libmusicbrainz5-dev libtinyxml2-dev texi2html openjdk-17-jdk \
          pkg-config ragel scons yasm)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_pkgs+=" $pkg"
        fi
    done

    if [ -n "$missing_pkgs" ]; then
        for pkg in "$missing_pkgs"
        do
            if sudo apt install $pkg; then
                echo 'The required development packages were installed.'
            else
                echo 'The required development packages failed to install'
                echo
                exit 1
            fi
        done
    else
        echo 'The required development packages are already installed.'
    fi
}

##
## ADDITIONAL REQUIRED GEFORCE CUDA DEVELOPMENT PACKAGES
##

cuda_add_fn()
{
    echo
    echo 'Installing required cuda developement packages'
    echo '================================================'

    pkgs=(autoconf automake build-essential libc6 \
          libc6-dev libnuma1 libnuma-dev texinfo unzip wget)

    for pkg in ${pkgs[@]}
    do
        if ! installed "$pkg"; then
            missing_pkgs+=" $pkg"
        fi
    done

    if [ -n "$missing_pkgs" ]; then
        for pkg in "$missing_pkgs"
        do
            sudo apt -y install $pkg
        done
        echo 'The required cuda developement packages were installed'
    else
        echo 'The required cuda developement packages are already installed'
    fi
}

install_cuda_fn()
{
    local cuda_ans cuda_choice

    iscuda="$(sudo find /usr/local/ -type f -name nvcc)"
    cudaPATH="$(sudo find /usr/local/ -type f -name nvcc | grep -Eo '^.*\/bi[n]?')"

    if [ -z "$iscuda" ]; then
        echo
        echo 'The cuda-sdk-toolkit isn'\''t installed or it is not in $PATH'
        echo '==============================================================='
        echo
        echo 'What do you want to do next?'
        echo
        echo '[1] Install the toolkit and add it to $PATH'
        echo '[2] Only add it to $PATH'
        echo '[3] Continue the build'
        echo
        read -p 'Your choices are (1 to 3): ' cuda_ans
        clear
        if [[ "$cuda_ans" -eq '1' ]]; then
            cuda_fn
            cuda_add_fn
        elif [[ "$cuda_ans" -eq '2' ]]; then
            if [ -d '/usr/local/cuda-12.1/bin' ]; then
                PATH="$PATH:$cudaPATH"
                export PATH
            else
                echo 'The script was unable to add cuda to your $PATH because the required folder was not found: /usr/local/cuda-12.1/bin'
                echo
                read -p 'Press enter to exit'
                echo
                exit 1
            fi
        elif [[ "$cuda_ans" -eq '3' ]]; then
            echo
        else
            echo
            echo 'Error: Bad user input!'
            echo '======================='
            fail_fn
        fi
    else
        echo
        echo "The cuda-sdk-toolkit v12.1 is already installed."
        echo '================================================='
        echo
        echo 'Do you want to update/reinstall it?'
        echo
        echo '[1] Yes'
        echo '[2] No'
        echo
        read -p 'Your choices are (1 or 2): ' cuda_choice
        clear
        if [[ "$cuda_choice" -eq '1' ]]; then
            cuda_fn
            cuda_add_fn
        elif [[ "$cuda_choice" -eq '2' ]]; then
            PATH="$PATH:$cudaPATH"
            export PATH
            echo 'Continuing the build...'
        else
            echo
            echo 'Bad user input.'
            echo
            read -p 'Press enter to try again.'
            clear
            install_cuda_fn
        fi
    fi
}

##
## install cuda
##

clear
install_cuda_fn

##
## build tools
##

# install required apt packages
build_pkgs_fn

##
## being source code building
##

git_test()
{
    git_url="$1"
    git_dir="$2"
    git_url+=" $3"
    eval "git clone '$git_url' $git_dir/"
}

# begin source code building
if build 'giflib' '5.2.1'; then
    download 'https://netcologne.dl.sourceforge.net/project/giflib/giflib-5.2.1.tar.gz' 'giflib-5.2.1.tar.gz'
    # PARELLEL BUILDING NOT AVAILABLE FOR THIS LIBRARY
    execute make
    execute make PREFIX="$workspace" install
    build_done 'giflib' '5.2.1'
fi

check_version 'pkgconf/pkgconf'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'pkgconf/pkgconf' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="$check_ver"
fi
if build 'pkg-config' "$g_ver"; then
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --silent --prefix="$workspace" --with-pc-path="$workspace"/lib/pkgconfig/ --with-internal-glib
    execute make -j "$cpu_threads"
    execute make install
    build_done 'pkg-config' "$g_ver"
fi

check_version 'yasm/yasm'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'yasm/yasm' '1' 'T'
    g_ver="${g_ver##*-}"
else
    clear
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'yasm' "$g_ver"; then
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "yasm-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'yasm' "$g_ver"
fi

if build 'nasm' '2.16.01'; then
    download "https://www.nasm.us/pub/nasm/releasebuilds/2.16.01/nasm-2.16.01.tar.xz" "nasm-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'nasm' '2.16.01'
fi

check_version 'madler/zlib'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'madler/zlib' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'zlib' "$g_ver"; then
    download "https://github.com/madler/zlib/releases/download/v$g_ver/zlib-$g_ver.tar.gz" "zlib-$g_ver.tar.gz"
    execute ./configure --static --prefix="$workspace"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'zlib' "$g_ver"
fi

if build 'm4' '1.4.19'; then
    download 'https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.xz'
    execute ./configure --prefix="$workspace" --enable-c++ --with-dmalloc
    execute make -j "$cpu_threads"
    execute make install
    build_done 'm4' '1.4.19'
fi

if build 'autoconf' '2.71'; then
    download 'https://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.xz'
    execute ./configure --prefix="$workspace"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'autoconf' '2.71'
fi

if build 'automake' '1.16.5'; then
    download 'https://ftp.gnu.org/gnu/automake/automake-1.16.5.tar.xz'
    execute ./configure --prefix="$workspace"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'automake' '1.16.5'
fi

if build 'libtool' '2.4.7'; then
    download 'https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.xz'
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libtool' '2.4.7'
fi

if $nonfree_and_gpl; then
    check_version 'openssl/openssl'
    if [ "$g_nocheck" -eq '1' ]; then
        git_ver_fn 'openssl/openssl' '1' 'R'
        g_ver="${g_ver##*-}"
    else
        echo 'gver = g_nocheck'
        g_ver="${check_ver##*-}"
    fi
    if build 'openssl' "$g_ver"; then
        download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "openssl-$g_ver.tar.gz"
        execute ./config --prefix="$workspace" --openssldir="$workspace" --with-zlib-include="$workspace"/include/ --with-zlib-lib="$workspace"/lib no-shared zlib
        execute make -j "$cpu_threads"
        execute make install_sw
        build_done 'openssl' "$g_ver"
    fi
    cnf_ops+=('--enable-openssl')
else
    if build 'gmp' '6.2.1'; then
        download 'https://ftp.gnu.org/gnu/gmp/gmp-6.2.1.tar.xz'
        execute ./configure --prefix="$workspace" --disable-shared --enable-static
        execute make -j "$cpu_threads"
        execute make install
        build_done 'gmp' '6.2.1'
    fi

    if build 'nettle' '3.8.1'; then
        download 'https://ftp.gnu.org/gnu/nettle/nettle-3.8.1.tar.gz'
        execute ./configure --prefix="$workspace" --disable-shared --enable-static --disable-openssl \
            --disable-documentation --libdir="$workspace"/lib CPPFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
        execute make -j "$cpu_threads"
        execute make install
        build_done 'nettle' '3.8.1'
    fi

    if build 'gnutls' '3.8.0'; then
        download 'https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.0.tar.xz'
        execute ./configure --prefix="$workspace" --disable-shared --enable-static --disable-doc --disable-tools \
            --disable-cxx --disable-tests --disable-gtk-doc-html --disable-libdane --disable-nls --enable-local-libopts \
            --disable-guile --with-included-libtasn1 --with-included-unistring --without-p11-kit CPPFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
        execute make -j "$cpu_threads"
        execute make install
        build_done 'gnutls' '3.8.0'
    fi
    cnf_ops+=('--enable-gmp' '--enable-gnutls')
fi

check_version 'kitware/cmake'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'kitware/cmake' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'cmake' "$g_ver" "$packages/$1.done"; then
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "cmake-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --parallel="$cpu_threads" --enable-ccache -- -DCMAKE_USE_OPENSSL='OFF'
    execute make -j "$cpu_threads"
    execute sudo make install
    build_done 'cmake' "$g_ver"
fi

##
## video libraries
##

if command_exists 'python3'; then
    # dav1d needs meson and ninja along with nasm to be built
    if command_exists 'pip3'; then
        # meson and ninja can be installed via pip3
        pip_tools_pkg="$(pip3 show setuptools)"
        if [ -z "$pip_tools_pkg" ]; then
            execute pip3 install pip setuptools --quiet --upgrade --no-cache-dir --disable-pip-version-check
        fi
    for r in meson ninja
    do
        if ! command_exists $r; then
            execute pip3 install $r --quiet --upgrade --no-cache-dir --disable-pip-version-check
        fi
        export PATH="$PATH:${HOME}/Library/Python/3.9/bin"
    done
    fi
    if command_exists 'meson'; then
        git_ver_fn '198' '2' 'T'
        if build 'dav1d' "$g_sver"; then
            download "https://code.videolan.org/videolan/dav1d/-/archive/$g_ver/$g_ver.tar.bz2" "dav1d-$g_sver.tar.bz2"
            make_dir build
            CFLAGSBACKUP="$CFLAGS"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'dav1d' "$g_sver"
        fi
        cnf_ops+=('--enable-libdav1d')
    fi
fi

git_ver_fn '24327400' '3' 'T'
if build 'svtav1' "$g_ver"; then
    download "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$g_ver/SVT-AV1-v$g_ver.tar.bz2" "SVT-AV1-$g_ver.tar.bz2"
    cd Build/linux || exit 1
    execute cmake -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' ../.. -G'Unix Makefiles' -DCMAKE_BUILD_TYPE='Release'
    execute make -j "$cpu_threads"
    execute make install
    execute cp 'SvtAv1Enc.pc' "$workspace"/lib/pkgconfig/
    execute cp 'SvtAv1Dec.pc' "$workspace"/lib/pkgconfig/
    build_done 'svtav1' "$g_ver"
fi
cnf_ops+=('--enable-libsvtav1')

if command_exists 'cargo'; then
    check_version 'xiph/rav1e'
    if [ "$g_nocheck" -eq '1' ]; then
        git_ver_fn 'xiph/rav1e' '1' 'T'
        g_ver="${g_ver##*-}"
    else
        echo 'gver = g_nocheck'
        g_ver="${check_ver##*-}"
    fi
    if build 'rav1e' "$g_ver"; then
        execute cargo install --version '0.9.14+cargo-0.66' cargo-c
        download "$g_url" "rav1e-$g_ver.tar.gz"
        execute cargo cinstall --prefix="$workspace" --library-type='staticlib' --crt-static --release
        build_done 'rav1e' "$g_ver"
    fi
    avif_tag='-DAVIF_CODEC_RAV1E=ON'
    cnf_ops+=('--enable-librav1e')
else
    avif_tag='-DAVIF_CODEC_RAV1E=OFF'
fi

if $nonfree_and_gpl; then
    git_ver_fn '536' '2' 'B'
    if build 'x264' "$g_sver"; then
        download "https://code.videolan.org/videolan/x264/-/archive/$g_ver/x264-$g_ver.tar.bz2" "x264-$g_sver.tar.bz2"
        execute ./configure --prefix="$workspace" --enable-static --enable-pic CXXFLAGS="-fPIC $CXXFLAGS"
        execute make -j "$cpu_threads"
        execute make install
        execute make install-lib-static
        build_done 'x264' "$g_sver"
    fi
    cnf_ops+=('--enable-libx264')
fi

if $nonfree_and_gpl; then
    git_ver_fn 'x265_git' '5' 'X'
    if build 'x265' '3.5'; then
        download 'https://github.com/videolan/x265/archive/Release_3.5.tar.gz' 'x265-3.5.tar.gz'
        cd 'build/linux' || exit 1
        rm -fr {8,10,12}bit 2>/dev/null
        mkdir -p {8,10,12}bit
        cd 12bit || exit 1
        echo '$ making 12bit binaries'
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' \
            -DHIGH_BIT_DEPTH='ON' -DENABLE_HDR10_PLUS='ON' -DEXPORT_C_API='OFF' -DENABLE_CLI='OFF' -DMAIN12='ON'
        execute make -j "$cpu_threads"
        echo '$ making 10bit binaries'
        cd ../10bit || exit 1
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' \
            -DHIGH_BIT_DEPTH='ON' -DENABLE_HDR10_PLUS='ON' -DEXPORT_C_API='OFF' -DENABLE_CLI='OFF'
        execute make -j "$cpu_threads"
        echo '$ making 8bit binaries'
        cd ../8bit || exit 1
        ln -sf ../10bit/libx265.a libx265_main10.a
        ln -sf ../12bit/libx265.a libx265_main12.a
        execute cmake ../../../source -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' \
            -DEXTRA_LIB='x265_main10.a;x265_main12.a;-ldl' -DEXTRA_LINK_FLAGS='-L.' -DLINKED_10BIT='ON' -DLINKED_12BIT='ON'
        execute make -j "$cpu_threads"
        mv libx265.a  libx265_main.a

        execute ar -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF

        execute make install

        if [ -n "$LDEXEFLAGS" ]; then
            sed -i.backup 's/-lgcc_s/-lgcc_eh/g' "$workspace/lib/pkgconfig/x265.pc"
        fi

        build_done 'x265' '3.5'
    fi
    cnf_ops+=('--enable-libx265')
fi

check_version 'openvisualcloud/svt-hevc'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'openvisualcloud/svt-hevc' '1' 'R'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'SVT-HEVC' "$g_ver"; then
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "SVT-HEVC-$g_ver.tar.gz"
    make_dir Build
    cd "$PWD"/Build || exit 1
    execute cmake .. -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' -DCMAKE_BUILD_TYPE='Release'
    execute make -j "$cpu_threads"
    execute make install
    build_done 'SVT-HEVC' "$g_ver"
fi

check_version 'webmproject/libvpx'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'webmproject/libvpx' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'libvpx' "$g_ver"; then
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "libvpx-$g_ver.tar.gz"
    execute ./configure --prefix="$workspace" --disable-unit-tests --disable-shared --disable-examples --as='yasm'
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libvpx' "$g_ver"
fi
cnf_ops+=('--enable-libvpx')

if $nonfree_and_gpl; then
    if build 'xvidcore' '1.3.7'; then
        download 'https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.bz2'
        cd 'build/generic' || exit 1
        execute ./configure --prefix="$workspace" --disable-shared --enable-static
        execute make -j "$cpu_threads"
        execute make install

        if [[ -f "$workspace"/lib/libxvidcore.4.dylib ]]; then
            execute rm "$workspace"/lib/libxvidcore.4.dylib
        fi

        if [[ -f "$workspace"/lib/libxvidcore.so ]]; then
            execute rm "$workspace"/lib/libxvidcore.so*
        fi

        build_done 'xvidcore' '1.3.7'
    fi
    cnf_ops+=('--enable-libxvid')
fi

check_version 'georgmartius/vid.stab'
    if [ "$g_nocheck" -eq '1' ]; then
        git_ver_fn 'georgmartius/vid.stab' '1' 'T'
        g_ver="${g_ver##*-}"
    else
        echo 'gver = g_nocheck'
        g_ver="${check_ver##*-}"
    fi
    if $nonfree_and_gpl; then
    if build 'vid_stab' "$g_ver"; then
        download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "vid.stab-$g_ver.tar.gz"
        execute cmake -DBUILD_SHARED_LIBS='OFF' -DCMAKE_INSTALL_PREFIX="$workspace" -DUSE_OMP='OFF' -DENABLE_SHARED='OFF' .
        execute make -j "$cpu_threads"
        execute make install
        build_done 'vid_stab' "$g_ver"
    fi
    cnf_ops+=('--enable-libvidstab')
fi

if build 'av1' '5711b50'; then
    download 'https://aomedia.googlesource.com/aom/+archive/5711b50eebe392119defd2a2a262bffef05e8507.tar.gz' 'av1.tar.gz' 'av1'
    make_dir "$packages"/aom_build
    cd "$packages"/aom_build || exit 1
    execute cmake -DENABLE_TESTS='0' -DENABLE_EXAMPLES='0' -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' "$packages"/av1
    execute make -j "$cpu_threads"
    execute make install
    build_done 'av1' '5711b50'
fi
cnf_ops+=('--enable-libaom')

check_version 'sekrit-twc/zimg'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'sekrit-twc/zimg' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'zimg' "$g_ver"; then
    download "https://github.com/sekrit-twc/zimg/archive/refs/tags/release-$g_ver.tar.gz" "zimg-$g_ver.tar.gz"
    execute "$workspace"/bin/libtoolize -i -f -q
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'zimg' "$g_ver"
fi
cnf_ops+=('--enable-libzimg')

if build "libpng" '1.6.39'; then
    download_git 'https://github.com/glennrp/libpng.git' 'libpng-1.6.39'
    export LDFLAGS="${LDFLAGS}"
    export CPPFLAGS="${CFLAGS}"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute sudo make install
  build_done "libpng" '1.6.39'
fi

check_version 'AOMediaCodec/libavif'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'AOMediaCodec/libavif' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'avif' "$g_ver"; then
    export CFLAGS+="-I$CFLAGS -I$workspace/include"
    download "https://github.com/AOMediaCodec/libavif/archive/refs/tags/v$g_ver.tar.gz" "avif-$g_ver.tar.gz"
    execute cmake -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' \
        -DENABLE_STATIC='ON' -DAVIF_ENABLE_WERROR='OFF' -DAVIF_CODEC_DAV1D='ON' -DAVIF_CODEC_AOM='ON' -G'Unix Makefiles' \
        -DAVIF_BUILD_APPS='ON' "$avif_tag"
    execute make -j "$cpu_threads"
    execute make install
    build_done 'avif' "$g_ver"
fi

check_version 'ultravideo/kvazaar'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'ultravideo/kvazaar' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'kvazaar' "$g_ver"; then
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "kvazaar-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-static --disable-shared
    execute make -j "$cpu_threads"
    execute make install
    build_done 'kvazaar' "$g_ver"
fi
cnf_ops+=('--enable-libkvazaar')

##
## audio libraries
##

if command_exists 'python3'; then
    if command_exists 'meson'; then
        check_version 'lv2/lv2'
        if [ "$g_nocheck" -eq '1' ]; then
            git_ver_fn 'lv2/lv2' '1' 'T'
            g_ver="${g_ver##*-}"
        else
            echo
            echo 'gver = g_nocheck'
            g_ver="${check_ver##*-}"
        fi
        if build 'lv2' "$g_ver"; then
            download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "lv2-$g_ver.tar.gz"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'lv2' "$g_ver"
        fi

        git_ver_fn '7131569' '3' 'T'
        if build 'waflib' "$g_ver"; then
            download "https://gitlab.com/ita1024/waf/-/archive/$g_ver/waf-$g_ver.tar.bz2" "autowaf-$g_ver.tar.bz2"
            build_done 'waflib' "$g_ver"
        fi

        git_ver_fn '5048975' '3' 'T'
        if build 'serd' "$g_ver"; then
            download "https://gitlab.com/drobilla/serd/-/archive/v$g_ver/serd-v$g_ver.tar.bz2" "serd-$g_ver.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
            execute ninja -C build
            execute ninja -C build install
            build_done 'serd' "$g_ver"
        fi

        check_version 'pcre2project/pcre2'
        if [ "$g_nocheck" -eq '1' ]; then
            git_ver_fn 'pcre2project/pcre2' '1' 'T'
            g_ver="${g_ver##*-}"
        else
            echo
            echo 'gver = g_nocheck'
            g_ver="${check_ver##*-}"
        fi
        if build 'pcre2' "$g_ver"; then
            download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "pcre2-$g_ver.tar.gz"
            execute ./autogen.sh
            execute ./configure --prefix="$workspace" --disable-shared --enable-static
            execute make -j "$cpu_threads"
            execute make install
            build_done 'pcre2' "$g_ver"
        fi

        git_ver_fn '14889806' '3' 'B'
        if build 'zix' "$g_sver1"; then
            download "https://gitlab.com/drobilla/zix/-/archive/$g_ver1/zix-$g_ver1.tar.bz2" "zix-$g_sver1.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' \
                --backend 'ninja' --pkg-config-path="$workspace"/lib/pkgconfig
            execute ninja -C build
            execute ninja -C build install
            build_done 'zix' "$g_sver1"
        fi

        git_ver_fn '11853362' '3' 'T'
        if build 'sord' "$g_ver"; then
            download "https://gitlab.com/drobilla/sord/-/archive/v$g_ver/sord-v$g_ver.tar.bz2" "sord-$g_ver.tar.bz2"
            meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' \
                --libdir="$workspace"/lib  --pkg-config-path="$workspace"/lib/pkgconfig
            execute ninja -C build
            execute ninja -C build install
            build_done 'sord' "$g_ver"
        fi

        git_ver_fn '11853194' '3' 'T'
        if build 'sratom' "$g_ver"; then
            download "https://gitlab.com/lv2/sratom/-/archive/v$g_ver/sratom-v$g_ver.tar.bz2" "sratom-$g_ver.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' \
                --libdir="$workspace"/lib --pkg-config-path="$workspace"/lib/pkgconfig
            execute ninja -C build
            execute ninja -C build install
            build_done 'sratom' "$g_ver"
        fi

        git_ver_fn '11853176' '3' 'T'
        if build 'lilv' "$g_ver"; then
            download "https://gitlab.com/lv2/lilv/-/archive/v$g_ver/lilv-v$g_ver.tar.bz2" "lilv-$g_ver.tar.bz2"
            execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' \
                --libdir="$workspace"/lib --pkg-config-path="$workspace"/lib/pkgconfig
            execute ninja -C build
            execute ninja -C build install
            build_done 'lilv' "$g_ver"
        fi
        CFLAGS+=" -I$workspace/include/lilv-0"
        cnf_ops+=('--enable-lv2')
    fi
fi

if build 'opencore' '0.1.6'; then
    download 'https://master.dl.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-0.1.6.tar.gz?viasf=1' 'opencore-amr-0.1.6.tar.gz'
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'opencore' '0.1.6'
fi
cnf_ops+=('--enable-libopencore_amrnb' '--enable-libopencore_amrwb')

if build 'lame' '3.100'; then
    download 'https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download?use_mirror=gigenet' 'lame-3.100.tar.gz'
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'lame' '3.100'
fi
cnf_ops+=('--enable-libmp3lame')

check_version 'xiph/opus'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'xiph/opus' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'opus' "$g_ver"; then
    download "https://github.com/xiph/opus/archive/refs/tags/v$g_ver.tar.gz" "opus-$g_ver.tar.gz"
    execute ./autogen.sh
    execute cmake -DCMAKE_INSTALL_PREFIX="$workspace" -DENABLE_SHARED='OFF' -DBUILD_SHARED_LIBS='OFF' \
        -DENABLE_STATIC='ON' -G'Unix Makefiles'
    execute make -j "$cpu_threads"
    execute make install
    build_done 'opus' "$g_ver"
fi
cnf_ops+=('--enable-libopus')

check_version 'xiph/ogg'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'xiph/ogg' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'libogg' "$g_ver"; then
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "libogg-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libogg' "$g_ver"
fi

check_version 'xiph/vorbis'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'xiph/vorbis' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'libvorbis' "$g_ver"; then
    download "https://github.com/xiph/vorbis/archive/refs/tags/v$g_ver.tar.gz" "libvorbis-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --with-ogg-libraries="$workspace"/lib \
        --with-ogg-includes="$workspace"/include --enable-static --disable-shared --disable-oggtest
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libvorbis' "$g_ver"
fi
cnf_ops+=('--enable-libvorbis')

check_version 'xiph/theora'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'xiph/theora' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'libtheora' "$g_ver"; then
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "libtheora-$g_ver.tar.gz"
    execute autoreconf -isf
    sed 's/-fforce-addr//g' 'configure' >'configure.patched'
    chmod +x 'configure.patched'
    mv 'configure.patched' 'configure'
    rm 'config.guess'
    curl -Lso 'config.guess' 'https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess'
    chmod +x 'config.guess'
    execute ./configure --prefix="$workspace" --with-ogg-libraries="$workspace"/lib --with-ogg-includes="$workspace"/include/ \
        --with-vorbis-libraries="$workspace"/lib --with-vorbis-includes="$workspace"/include/ --enable-static --disable-shared \
        --disable-oggtest --disable-vorbistest --disable-examples --disable-asm --disable-spec
    make -j "$cpu_threads"
    execute make install
    build_done 'libtheora' "$g_ver"
fi
cnf_ops+=('--enable-libtheora')

if $nonfree_and_gpl; then
check_version 'mstorsjo/fdk-aac'
    if [ "$g_nocheck" -eq '1' ]; then
        git_ver_fn 'mstorsjo/fdk-aac' '1' 'T'
        g_ver="${g_ver##*-}"
    else
        echo
        echo 'gver = g_nocheck'
        g_ver="${check_ver##*-}"
    fi
    if build 'fdk_aac' "$g_ver"; then
        download "https://github.com/mstorsjo/fdk-aac/archive/refs/tags/v$g_ver.tar.gz" "fdk_aac-$g_ver.tar.gz"
        execute ./autogen.sh
        execute ./configure --prefix="$workspace" --disable-shared --enable-static --enable-pic --bindir="$workspace"/bin CXXFLAGS=' -fno-exceptions -fno-rtti'
        execute make -j "$cpu_threads"
        execute make install
        build_done 'fdk_aac' "$g_ver"
    fi
    cnf_ops+=('--enable-libfdk-aac')
fi

##
## image libraries
##

git_ver_fn '4720790' '3' 'T'
if build 'libtiff' "$g_ver"; then
    download "https://gitlab.com/libtiff/libtiff/-/archive/v$g_ver/libtiff-v$g_ver.tar.bz2" "libtiff-$g_ver.tar.bz2"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libtiff' "$g_ver"
fi

if build 'libwebp' 'git'; then
    # libwebp can fail to compile on ubuntu if cflags are set
    # version 1.3.0, 1.2.4, and 1.2.3 fail to build successfully
    CPPFLAGS=
    download_git 'https://chromium.googlesource.com/webm/libwebp' 'libwebp-git'
    execute ./autogen.sh
    make_dir build
    cd build || exit 1
    execute cmake -DCMAKE_INSTALL_PREFIX="/home/jman/tmp/ffmpeg/workspace" -DCMAKE_INSTALL_LIBDIR='lib' \
        -DCMAKE_INSTALL_BINDIR='bin' -DCMAKE_INSTALL_INCLUDEDIR='include' -DENABLE_SHARED='OFF' -DENABLE_STATIC='ON' -DWEBP_BUILD_CWEBP='ON' -DWEBP_BUILD_DWEBP='ON' ../
    execute make -j "$cpu_threads"
    execute sudo make install
    build_done 'libwebp' 'git'
fi
cnf_ops+=('--enable-libwebp')

##
## other libraries
##

git_ver_fn '363' '2' 'T'
if build 'udfread' "$g_ver1"; then
    download "https://code.videolan.org/videolan/libudfread/-/archive/$g_ver1/libudfread-$g_ver1.tar.bz2" "udfread-$g_ver1.tar.bz2"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared --enable-static --with-pic --with-gnu-ld
    execute make -j "$cpu_threads"
    execute make install
    build_done 'udfread' "$g_ver1"
fi

git_ver_fn '206' '2' 'T'
if build 'libbluray' "$g_ver1"; then
    download "https://code.videolan.org/videolan/libbluray/-/archive/$g_ver1/$g_ver1.tar.gz" "libbluray-$g_ver1.tar.gz"
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libbluray' "$g_ver1"
fi
unset JAVA_HOME
cnf_ops+=('--enable-libbluray')

check_version 'mediaarea/zenLib'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'mediaarea/zenLib' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'zenLib' "$g_ver"; then
    download "https://github.com/MediaArea/ZenLib/archive/refs/tags/v$g_ver.tar.gz" "zenLib-$g_ver.tar.gz"
    cd Project/CMake || exit 1
    execute cmake -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' -DCMAKE_INSTALL_BINDIR='bin' \
        -DCMAKE_INSTALL_INCLUDEDIR='include' -DENABLE_SHARED='OFF' -DENABLE_STATIC='ON'
    execute make -j "$cpu_threads"
    execute make install
    build_done 'zenLib' "$g_ver"
fi

check_version 'MediaArea/MediaInfoLib'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'MediaArea/MediaInfoLib' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'MediaInfoLib' "$g_ver"; then
    download "https://github.com/MediaArea/MediaInfoLib/archive/refs/tags/v$g_ver.tar.gz" "MediaInfoLib-$g_ver.tar.gz"
    cd Project/CMake || exit 1
    execute cmake . -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' -DCMAKE_INSTALL_BINDIR='bin' \
        -DCMAKE_INSTALL_INCLUDEDIR='include' -DENABLE_SHARED='OFF' -DENABLE_STATIC='ON' -DENABLE_APPS='OFF' \
        -DUSE_STATIC_LIBSTDCXX='ON' -DBUILD_ZLIB='OFF' -DBUILD_ZENLIB='OFF'
    execute make -j "$cpu_threads"
    execute make install
    build_done 'MediaInfoLib' "$g_ver"
fi

check_version 'MediaArea/MediaInfo'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'MediaArea/MediaInfo' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'MediaInfoCLI' "$g_ver"; then
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "MediaInfoCLI-$g_ver.tar.gz"
    cd "$PWD"/Project/GNU/CLI || exit 1
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --enable-staticlibs
    build_done 'MediaInfoCLI' "$g_ver"
fi

if command_exists 'meson'; then
    check_version 'harfbuzz/harfbuzz'
    if [ "$g_nocheck" -eq '1' ]; then
        git_ver_fn 'harfbuzz/harfbuzz' '1' 'R'
        g_ver="${g_ver##*-}"
    else
        echo
        echo 'gver = g_nocheck'
        g_ver="${check_ver##*-}"
    fi
    if build 'harfbuzz' "$g_ver"; then
        download "https://github.com/harfbuzz/harfbuzz/archive/refs/tags/$g_ver.tar.gz" "harfbuzz-$g_ver.tar.gz"
        execute ./autogen.sh
        execute meson setup build --prefix="$workspace" --buildtype='release' --default-library='static' --libdir="$workspace"/lib
        execute ./configure --prefix="$workspace" --disable-shared --enable-static
        execute ninja -C build
        execute ninja -C build install
        build_done 'harfbuzz' "$g_ver"
    fi
fi

if build 'c2man' 'git'; then
    download_git 'https://github.com/fribidi/c2man.git' 'c2man-git'
    execute ./Configure -desO -D prefix="$workspace" -D bin="$workspace/bin" -D bash='/bin/bash' -D cc='/usr/lib/ccache/cc' \
        -D d_gnu='/usr/lib/x86_64-linux-gnu' -D find='/usr/bin/find' -D gcc='/usr/lib/ccache/gcc' -D gzip='/usr/bin/gzip' \
        -D installmansrc="$workspace/share/man" -D ldflags=" -L $workspace/lib -L/usr/local/lib" -D less='/usr/bin/less' \
        -D libpth="$workspace/lib /usr/local/lib /lib /usr/lib" \
        -D locincpth="$workspace/include /usr/local/include /opt/local/include /usr/gnu/include /opt/gnu/include /usr/GNU/include /opt/GNU/include" \
        -D yacc='/usr/bin/yacc' -D loclibpth="$workspace/lib /usr/local/lib /opt/local/lib /usr/gnu/lib /opt/gnu/lib /usr/GNU/lib /opt/GNU/lib" \
        -D make='/usr/bin/make' -D more='/usr/bin/more' -D osname='Ubuntu' -D perl='/usr/bin/perl' -D privlib="$workspace/lib/c2man" \
        -D privlibexp="$workspace/lib/c2man" -D sleep='/usr/bin/sleep' -D tail='/usr/bin/tail' -D tar='/usr/bin/tar' -D uuname='Linux' \
        -D vi='/usr/bin/vi' -D zip='/usr/bin/zip'
    execute make depend
    execute make -j "$cpu_threads"
    execute sudo make install
    build_done 'c2man' 'git'
fi

check_version 'fribidi/fribidi'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'fribidi/fribidi' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'fribidi' "$g_ver"; then
    if [ -f "fribidi-$g_ver.tar.gz" ]; then
        sudo rm "fribidi-$g_ver.tar.gz"
    fi
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "fribidi-$g_ver.tar.gz"
    execute meson setup build --prefix="/home/jman/tmp/ffmpeg/workspace" --strip --backend ninja --optimization 3 \
        --pkg-config-path="$PKG_CONFIG_PATH"--buildtype='release' --default-library='static' --libdir="/home/jman/tmp/ffmpeg/workspace"/lib
    execute ninja -C build
    execute ninja -C build install
    build_done 'fribidi' "$g_ver"
fi
cnf_ops+=('--enable-libfribidi')

check_version 'libass/libass'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'libass/libass' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'libass' "$g_ver"; then
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "libass-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libass' "$g_ver"
fi
cnf_ops+=('--enable-libass')

git_ver_fn '890' '4'
if build 'fontconfig' "$g_ver"; then
    extracommands=(-D{harfbuzz,png,bzip2,brotli,zlib,tests}"=disabled")
    download "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/$g_ver/fontconfig-$g_ver.tar.bz2" "fontconfig-$g_ver.tar.bz2"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --sysconfdir="$workspace"/etc/ --mandir="$workspace"/share/man/
    execute make -j "$cpu_threads"
    execute make install
    build_done 'fontconfig' "$g_ver"
fi
cnf_ops+=('--enable-libfontconfig')

git_ver_fn '7950' '4'
if build 'freetype' "$g_ver"; then
    extracommands=(-D{harfbuzz,png,bzip2,brotli,zlib,tests}"=disabled")
    download "https://gitlab.freedesktop.org/freetype/freetype/-/archive/$g_ver/freetype-$g_ver.tar.bz2" "freetype-$g_ver.tar.bz2"
    execute ./autogen.sh
    execute cmake -S . -B build/release-static -DCMAKE_INSTALL_PREFIX="$workspace" \
        -DVVDEC_ENABLE_LINK_TIME_OPT='OFF' -DCMAKE_VERBOSE_MAKEFILE='OFF' -DCMAKE_BUILD_TYPE='Release' "${extracommands[@]}"
    execute cmake --build build/release-static -j "$cpu_threads"
    build_done 'freetype' "$g_ver"
fi
cnf_ops+=('--enable-libfreetype')

check_version 'libsdl-org/SDL'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'libsdl-org/SDL' '1' 'R'
    g_ver="${g_ver##*-}"
else
    echo
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'libsdl' "$g_ver"; then
    download "https://github.com/libsdl-org/SDL/archive/refs/tags/release-$g_ver.tar.gz" "libsdl-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" --disable-shared --enable-static
    execute make -j "$cpu_threads"
    execute make install
    build_done 'libsdl' "$g_ver"
fi

if $nonfree_and_gpl; then
    check_version 'Haivision/srt'
    if [ "$g_nocheck" -eq '1' ]; then
        git_ver_fn 'Haivision/srt' '1' 'T'
    else
        echo
        echo 'gver = g_nocheck'
        g_ver="${check_ver##srt-}"
    fi
    if build 'srt' "$g_ver"; then
        download "https://github.com/Haivision/srt/archive/refs/heads/master.tar.gz" "srt-$g_ver.tar.gz"
        export OPENSSL_ROOT_DIR="$workspace"
        export OPENSSL_LIB_DIR="$workspace"/lib
        export OPENSSL_INCLUDE_DIR="$workspace"/include/
        execute cmake . -DCMAKE_INSTALL_PREFIX="$workspace" -DCMAKE_INSTALL_LIBDIR='lib' -DCMAKE_INSTALL_BINDIR='bin' \
            -DCMAKE_INSTALL_INCLUDEDIR='include' -DENABLE_SHARED='OFF' -DENABLE_STATIC='ON' -DENABLE_APPS='OFF' -DUSE_STATIC_LIBSTDCXX='ON'
        execute make -j "$cpu_threads"
        execute make install

        if [ -n "$LDEXEFLAGS" ]; then
            sed -i.backup 's/-lgcc_s/-lgcc_eh/g' "$workspace"/lib/pkgconfig/srt.pc
        fi

        build_done 'srt' "$g_ver"
    fi
        cnf_ops+=('--enable-libsrt')
fi

#####################
## HWaccel library ##
#####################

check_version 'khronosgroup/opencl-headers'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'khronosgroup/opencl-headers' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'opencl' "$g_ver"; then
    CFLAGS+=" -DLIBXML_STATIC_FOR_DLL -DNOLIBTOOL"
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "opencl-$g_ver.tar.gz"
    execute cmake -S . -B build -DCMAKE_INSTALL_PREFIX="$workspace"
    execute cmake --build build --target install
    build_done 'opencl' "$g_ver"
fi
cnf_ops+=('--enable-opencl')

# Vaapi doesn't work well with static links FFmpeg.
if [ -z "$LDEXEFLAGS" ]; then
    # If the libva development SDK is installed, enable vaapi.
    if library_exists 'libva'; then
        if build 'vaapi' '1'; then
            build_done 'vaapi' '1'
        fi
        cnf_ops+=('--enable-vaapi')
    fi
fi

check_version 'GPUOpen-LibrariesAndSDKs/AMF'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'GPUOpen-LibrariesAndSDKs/AMF' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'amf' "$g_ver"; then
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "AMF-$g_ver.tar.gz"
    execute rm -fr "$workspace"/include/AMF
    execute mkdir -p "$workspace"/include/AMF
    execute cp -fr "$packages"/AMF-"$g_ver"/amf/public/include/* "$workspace"/include/AMF/
    build_done 'amf' "$g_ver"
fi
cnf_ops+=('--enable-amf')

check_version 'fraunhoferhhi/vvenc'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'fraunhoferhhi/vvenc' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'vvenc' "$g_ver"; then
    download "https://github.com/$github_repo/archive/refs/heads/master.tar.gz" "vvenc-$g_ver.tar.gz"
    execute cmake -S . -B build/release-static -DCMAKE_INSTALL_PREFIX="$workspace" \
        -DVVDEC_ENABLE_LINK_TIME_OPT='OFF' -DCMAKE_VERBOSE_MAKEFILE='OFF' -DCMAKE_BUILD_TYPE='Release'
    execute cmake --build build/release-static -j "$cpu_threads"
    build_done 'vvenc' "$g_ver"
fi
cnf_ops+=('--enable-nvenc')

check_version 'fraunhoferhhi/vvdec'
if [ "$g_nocheck" -eq '1' ]; then
    git_ver_fn 'fraunhoferhhi/vvdec' '1' 'T'
    g_ver="${g_ver##*-}"
else
    echo 'gver = g_nocheck'
    g_ver="${check_ver##*-}"
fi
if build 'vvdec' "$g_ver"; then
    download_git 'https://github.com/fraunhoferhhi/vvdec.git' "vvdec-$g_ver"
    execute cmake -S . -B build/release-static -DCMAKE_INSTALL_PREFIX="$workspace" \
        -DVVDEC_ENABLE_LINK_TIME_OPT='OFF' -DCMAKE_VERBOSE_MAKEFILE='OFF' -DCMAKE_BUILD_TYPE='Release'
    execute cmake --build build/release-static -j "$cpu_threads"
    build_done 'vvdec' "$g_ver"
fi
cnf_ops+=('--enable-nvdec')

if which 'nvcc' &>/dev/null ; then
    check_version 'FFmpeg/nv-codec-headers'
    if [ "$g_nocheck" -eq '1' ]; then
        git_ver_fn 'FFmpeg/nv-codec-headers' '1' 'T'
        g_ver="${g_ver##*-}"
    else
        echo 'gver = g_nocheck'
        g_ver="${check_ver##*-}"
    fi
    if build 'nv-codec' "$g_ver"; then
        download_git 'https://github.com/FFmpeg/nv-codec-headers.git' "nv-codec-$g_ver"
        execute make PREFIX="$workspace"
        execute make install PREFIX="$workspace"
        build_done 'nv-codec' "$g_ver"
    fi
    CFLAGS+=" -I/usr/local/cuda-12.1/targets/x86_64-linux/include -I/usr/local/cuda-12.1/include -I$workspace/usr/include -I$packages/nv-codec-n12.0.16.0/include"
    export CFLAGS
    LDFLAGS+=' -L/usr/local/cuda-12.1/targets/x86_64-linux/lib -L/usr/local/cuda-12.1/lib64'
    export LDFLAGS
    LDPATH='-lcudart'
    cnf_ops+=('--enable-cuda-nvcc' '--enable-cuvid' '--enable-cuda-llvm')

    if [ -z "$LDEXEFLAGS" ]; then
        cnf_ops+=('--enable-libnpp')
    fi

    gpu_arch_fn

    # https://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards/
    cnf_ops+=("--nvccflags=-gencode arch=$gpu_arch")
fi

##
## BUILD FFMPEG
##

# REMOVE ANY FILES FROM PRIOR RUNS
if [ -d "$packages/FFmpeg-git" ]; then
    rm -fr "$packages/FFmpeg-git"
fi

# CLONE FFMPEG FROM THE LATEST GIT RELEASE
build 'FFmpeg' 'git'
download 'https://github.com/FFmpeg/FFmpeg/archive/refs/heads/master.tar.gz' 'FFmpeg-git.tar.gz'
echo '$ ./configure'
./configure \
        "${cnf_ops[@]}" \
        --arch="$(uname -m)" \
        --prefix="$workspace" \
        --disable-debug \
        --disable-doc \
        --disable-shared \
        --enable-pthreads \
        --enable-static \
        --enable-small \
        --enable-version3 \
        --enable-ffnvcodec \
        --cpu="$cpu_cores" \
        --extra-cflags="$CFLAGS" \
        --extra-ldexeflags="$LDEXEFLAGS" \
        --extra-ldflags="$LDFLAGS" \
        --extra-libs="$EXTRALIBS" \
        --pkgconfigdir="$workspace/lib/pkgconfig" \
        --pkg-config-flags='--static'

# EXECUTE MAKE WITH PARALLEL PROCESSING
execute make -j "$cpu_threads"
# EXECUTE MAKE INSTALL
execute make install

# MOVE BINARIES TO '/usr/bin'
if which 'sudo' &>/dev/null; then
    sudo cp -f "$workspace/bin/ffmpeg" "$install_dir/ffmpeg"
    sudo cp -f "$workspace/bin/ffprobe" "$install_dir/ffprobe"
    sudo cp -f "$workspace/bin/ffplay" "$install_dir/ffplay"
else
    cp -f "$workspace/bin/ffmpeg" "$install_dir/ffmpeg"
    cp -f "$workspace/bin/ffprobe" "$install_dir/ffprobe"
    cp -f "$workspace/bin/ffplay" "$install_dir/ffplay"
fi

# CHECK THAT FILES WERE COPIED TO THE INSTALL DIRECTORY
if [ ! -f "$install_dir/ffmpeg" ]; then
    echo "Failed to copy: ffmpeg to $install_dir/"
fi
if [ ! -f "$install_dir/ffprobe" ]; then
    echo "Failed to copy: ffprobe to $install_dir/"
fi
if [ ! -f "$install_dir/ffplay" ]; then
    echo "Failed to copy: ffplay to $install_dir/"
fi

# DISPLAY FFMPEG'S VERSION
ff_ver_fn
# PROMPT THE USER TO CLEAN UP THE BUILD FILES
cleanup_fn
# DISPLAY A MESSAGE AT THE SCRIPT'S END
exit_fn
