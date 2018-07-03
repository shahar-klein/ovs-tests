#!/bin/bash
#
# Test vxlan rule outer mac is correct.
#

NIC=${1:-ens5f0}
FILTER=${FILTER}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_mlxdump

function __test_basic_vxlan() {
    local ip_src=$1
    local ip_dst=$2
    local skip
    # note: we support adding decap to vxlan interface only.
    vx=vxlan1
    vxlan_port=4789
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dev $NIC dstport $vxlan_port external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set dev $vx up
    tc qdisc add dev $vx ingress

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ifconfig $NIC up
    ip neigh add $ip_dst lladdr e4:11:22:11:55:55 dev $NIC

    reset_tc_nic $NIC
    reset_tc_nic $REP

    skip=skip_sw

    reset_tc $REP
    reset_tc $vx

    tc_filter add dev $vx protocol 0x806 parent ffff: prio 1 \
                flower \
                        $skip \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                        enc_src_ip $ip_src \
                        enc_dst_ip $ip_dst \
                        enc_dst_port $vxlan_port \
                        enc_key_id 100 \
                action tunnel_key unset \
                action mirred egress redirect dev $REP || return $?

    i=0 && mlxdump -d $PCI fsdump --type FT --gvmi=$i  --no_zero > /tmp/port$i

    reset_tc $NIC
    reset_tc $REP
    reset_tc $vx
    ip addr flush dev $NIC
    ip link del $vx
    tmp=`dmesg | tail -n20 | grep "encap size" | grep "too big"`
    if [ "$tmp" != "" ]; then
        err "$tmp"
    fi
}

function test_basic_vxlan_ipv4() {
    __test_basic_vxlan \
                        20.1.11.1 \
                        20.1.12.1
}


title "Test decap rule outer dst mac"
enable_switchdev
rm -f /tmp/port0
test_basic_vxlan_ipv4 || fail
found_mac=$(for i in `grep -A20 "action.*:0x2c" /tmp/port0 | grep outer_headers.dmac -m2 | cut -d: -f2` ; do echo -n ${i:2} ; done)

if [ -z "$found_mac" ]; then
    fail "Cannot find mac address in dump"
fi

mac=`cat /sys/class/net/$NIC/address | tr -d :`

echo "uplink mac is $mac and rule mac is $found_mac"
if [ "$mac" != "$found_mac" ]; then
    err
else
    success
fi

test_done