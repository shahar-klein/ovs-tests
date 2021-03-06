#!/bin/bash
#
#
# Bug SW #1487302: [upstream] failing to set mode switchdev when we have 127 vfs
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


probe_fs="/sys/class/net/$NIC/device/sriov_drivers_autoprobe"
probe=0
function disable_sriov_autoprobe() {
    if [ -e $probe_fs ]; then
        probe=`cat $probe_fs`
        echo 0 > $probe_fs
    fi
}

function restore_sriov_autoprobe() {
    if [ $probe == 1 ]; then
        echo 1 > $probe_fs
    fi
}

function cleanup() {
    config_sriov 2 $NIC
    restore_sriov_autoprobe
}

function test_127_reps() {
    local want=127

    title "Test 127 REPs"

    switch_mode_legacy
    disable_sriov_autoprobe
    echo "Config $want VFs"
    config_sriov $want $NIC
    enable_switchdev

    echo "Verify"
    mac=`cat /sys/class/net/$NIC/address | tr -d :`
    count=`grep $mac /sys/class/net/*/phys_switch_id 2>/dev/null | wc -l`
    # decr 1 for pf
    let count-=1
    if [ $count != $want ]; then
        err "Found $count reps but expected $want"
    fi
}


trap cleanup EXIT
start_check_syndrome
test_127_reps
echo Cleanup
cleanup
check_syndrome
test_done
