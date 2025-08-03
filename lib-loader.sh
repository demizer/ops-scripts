#!/bin/bash

# shellcheck disable=SC2034,SC2154,SC1090

err() { echo "[ERROR]: $*" >&2; exit 1; }

GLOBALLIB_DOWNLOADED=0

# Tries multiple methods to load lib.sh
function find_globallib(){
    # Re-defined in lib.sh but it is needed to find lib.sh
    current=$(readlink -e "$(dirname "$0")")
    if [[ -n ${kitmaker_top_link:-} ]] && [[ -L $kitmaker_top_link ]]; then
        globallib="$kitmaker_top_link/compute_installer/scripts/lib.sh"
    elif [[ -f "$current/cuda_scripts/lib.sh" ]]; then
        globallib="$current/cuda_scripts/lib.sh"
    else
        curl -s -O https://gitlab-master.nvidia.com/cuda-installer/packaging/cuda-scripts/-/raw/libsh-minor-improvements/lib.sh
#        curl -s -O https://gitlab-master.nvidia.com/cuda-installer/packaging/cuda-scripts/-/raw/main/lib.sh
        GLOBALLIB_DOWNLOADED=1
        globallib="$PWD/lib.sh"
    fi
    [[ -f $globallib ]] || err "could not retrieve globallib"
    echo "$globallib"
}

function load_libsh(){
    globallib=$(find_globallib)
    [[ -f $globallib ]] || err "could not retrieve globallib" && source "$globallib"
    [[ ${GLOBALLIB_DOWNLOADED} -eq 1 ]] && [[ ${debug:-0} -eq 1 ]] && echo "$this: lib.sh downloaded from gitlab!" >&2
    [[ ${debug:-0} -eq 1 ]] && echo -e "$this: loaded globallib=$globallib\n" >&2
}
