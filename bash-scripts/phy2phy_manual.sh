#!/bin/bash -x

SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. ${SRC_DIR}/banner.sh
echo $OVS_DIR $DPDK_DIR

# Variables #
HUGE_DIR=/dev/hugepages


function start_test {

	print_phy2phy_banner

	sudo umount $HUGE_DIR
	echo "Lets bind the ports to the kernel first"
	sudo $DPDK_DIR/tools/dpdk_nic_bind.py --bind=$KERNEL_NIC_DRV $DPDK_PCI1 $DPDK_PCI2
    mkdir -p $HUGE_DIR
	sudo mount -t hugetlbfs nodev $HUGE_DIR

	sudo modprobe uio
	sudo rmmod igb_uio.ko
	sudo insmod $DPDK_DIR/$DPDK_TARGET/kmod/igb_uio.ko
	sudo $DPDK_DIR/tools/dpdk_nic_bind.py --bind=igb_uio $DPDK_PCI1 $DPDK_PCI2

	sudo rm /usr/local/etc/openvswitch/conf.db
	sudo $OVS_DIR/ovsdb/ovsdb-tool create /usr/local/etc/openvswitch/conf.db $OVS_DIR/vswitchd/vswitch.ovsschema

	sudo $OVS_DIR/ovsdb/ovsdb-server --remote=punix:/usr/local/var/run/openvswitch/db.sock --remote=db:Open_vSwitch,Open_vSwitch,manager_options --pidfile --detach
    sudo $OVS_DIR/utilities/ovs-vsctl --no-wait init
    sudo $OVS_DIR/utilities/ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
    sudo $OVS_DIR/utilities/ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-lcore-mask="0x4"
    sudo $OVS_DIR/utilities/ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="1024,0"
    sudo $OVS_DIR/utilities/ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-hugepage-dir="$HUGE_DIR"

	sudo -E $OVS_DIR/vswitchd/ovs-vswitchd --pidfile unix:/usr/local/var/run/openvswitch/db.sock --log-file &
	sleep 22
	sudo $OVS_DIR/utilities/ovs-vsctl --timeout 10 del-br br0
	sudo $OVS_DIR/utilities/ovs-vsctl --timeout 10 add-br br0 -- set bridge br0 datapath_type=netdev
	sudo $OVS_DIR/utilities/ovs-vsctl --timeout 10 add-port br0 dpdk0 -- set Interface dpdk0 type=dpdk
	sudo $OVS_DIR/utilities/ovs-vsctl --timeout 10 add-port br0 dpdk1 -- set Interface dpdk1 type=dpdk

	sudo $OVS_DIR/utilities/ovs-ofctl del-flows br0
	sudo $OVS_DIR/utilities/ovs-ofctl add-flow br0 idle_timeout=0,in_port=1,action=output:2
	sudo $OVS_DIR/utilities/ovs-ofctl add-flow br0 idle_timeout=0,in_port=2,action=output:1
	#sudo $OVS_DIR/utilities/ovs-ofctl add-flow br0 idle_timeout=0,in_port=2,dl_dst=03:00:00:00:00:03,nw_dst=192.168.2.101,action=output:1
	sudo $OVS_DIR/utilities/ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask="$PMD_CPU_MASK"
	sudo $OVS_DIR/utilities/ovs-ofctl dump-flows br0
	sudo $OVS_DIR/utilities/ovs-ofctl dump-ports br0
	sudo $OVS_DIR/utilities/ovs-vsctl show
	echo "Finished setting up the bridge, ports and flows..."
}

function kill_switch {
	echo "Killing the switch.."
	sudo $OVS_DIR/utilities/ovs-appctl -t ovs-vswitchd exit
	sudo $OVS_DIR/utilities/ovs-appctl -t ovsdb-server exit
	sleep 1
    sudo pkill -9 ovs-vswitchd
    sudo pkill -9 ovsdb-server
	sudo umount $HUGE_DIR
    sudo pkill -9 qemu-system-x86_64*
    sudo rm -rf /usr/local/var/run/openvswitch/*
    sudo rm -rf /usr/local/var/log/openvswitch/*
    sudo pkill -9 pmd*
}

function menu {
        echo "launching Switch.."
	    kill_switch
    	start_test
}
