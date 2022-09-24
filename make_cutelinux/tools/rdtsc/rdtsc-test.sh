#!/usr/bin/env bash

bin_PROGRAM=rdtsc.bin


nr_cpu=$(cat /proc/cpuinfo 2>/dev/null | grep "processor"| wc -l)

print_tsc() {
    local core=$1
    local ret1
    local ret2
    local ret

    ret1=$(taskset -c $core $bin_PROGRAM)
    sleep 10
    ret2=$(taskset -c $core $bin_PROGRAM)
    ret=$(expr $ret2 - $ret1)
    echo -e ">>> $core\t$ret"
}

cnt=0
while true; do
    print_tsc $cnt &

    cnt=$(expr $cnt + 1)

    if [ x"$cnt" == x"$nr_cpu" ]; then
        break
    fi
done



