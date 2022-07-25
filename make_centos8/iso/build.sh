#!/bin/bash

cd $(dirname $0)

_iso_dir="$1"

declare -A package_dirs
package_dirs=(
["BaseOS"]="${_iso_dir}/BaseOS"
["AppStream"]="${_iso_dir}/AppStream"
)

for key in ${!package_dirs[@]}; do
    if [ ! -e ${package_dirs[$key]} ]; then
        echo "[Err] ${package_dirs[$key]} not found!"
        exit 1
    fi
    if [ -e ${package_dirs[$key]}.bak ]; then
        echo "[Err] ${package_dirs[$key]}.bak has been exsit!"
        exit 1
    fi
    mv ${package_dirs[$key]} ${package_dirs[$key]}.bak
    mkdir -p ${package_dirs[$key]}/Packages
done

for key in ${!package_dirs[@]}; do
    for pkg in $(cat ${key}/rpm.list); do
        file_path="${package_dirs[$key]}.bak/Packages/${pkg}"
        if [ -e "${file_path}" ]; then
            mv ${file_path} ${package_dirs[$key]}/Packages/
        fi
    done
done

for key in ${!package_dirs[@]}; do
    rm -rf ${package_dirs[$key]}.bak
    cp -f ${key}/comps.xml ${package_dirs[$key]}/
    if [ x"$key" == x"AppStream" ]; then
        cp -f ${key}/modules.yaml ${package_dirs[$key]}/
    fi
    pushd ${package_dirs[$key]}
        createrepo_c -g comps.xml .
        rm -f comps.xml
        if [ x"$key" == x"AppStream" ]; then
            modifyrepo_c --mdtype=modules modules.yaml repodata/
            rm -f modules.yaml
        fi
    popd
done


exit 0
