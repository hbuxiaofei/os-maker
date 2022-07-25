#!/bin/bash

set -e

cd $(dirname $0)

_iso_dir="$1"

declare -A package_dirs
package_dirs=(
["BaseOS"]="${_iso_dir}"
)

for key in ${!package_dirs[@]}; do
    if [ ! -e ${package_dirs[$key]}/Packages ]; then
        echo "[Err] ${package_dirs[$key]}/Packages not found!"
        exit 1
    fi
    if [ -e ${package_dirs[$key]}/Packages.bak ]; then
        echo "[Err] ${package_dirs[$key]}/Packages.bak has been exsit!"
        exit 1
    fi
    mv ${package_dirs[$key]}/Packages ${package_dirs[$key]}/Packages.bak
    mkdir -p ${package_dirs[$key]}/Packages
done

for key in ${!package_dirs[@]}; do
    for pkg in $(cat ${key}/rpm.list); do
        file_path="${package_dirs[$key]}/Packages.bak/${pkg}"
        if [ -e "${file_path}" ]; then
            mv ${file_path} ${package_dirs[$key]}/Packages/
        fi
    done
done

for key in ${!package_dirs[@]}; do
    rm -rf ${package_dirs[$key]}/repodata
    rm -rf ${package_dirs[$key]}/Packages.bak
    cp -f ${key}/comps.xml ${package_dirs[$key]}/
    pushd ${package_dirs[$key]}
        createrepo -g comps.xml .
        rm -f comps.xml
    popd
done


exit 0
