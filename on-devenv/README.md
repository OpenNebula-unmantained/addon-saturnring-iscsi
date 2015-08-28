# OpenNebula Development Environment

The [sandbox OpenNebula VM](http://opennebula.org/tryout/sandboxvirtualbox/) is an all-in-one OpenNebula setup (Front-end, hypervisor, Sunstone). But developing/testing opportunities are limited because only 1 hypervisor is available (so VM migration testing is not possible). In addition, the hypervisor it runs on - Virtualbox - does not work well with nested virtualization, limiting the developer to only 32-bit VMs. In order to simplify further development of the driver in OpenNebula a virtualized test environment setup with Vagrant and KVM (which does allow nested virtualization for recent Linux Kernels > v3.16) here. Note that it is not possible to run both virtualbox and KVM on the same host at present.

The setup described here creates a Vagrant-based OpenNebula environment. One (beefy) computer or server can be made to emulate an OpenNebula setup with a Front-end and two hypervisors (which in turn can run multiple kvm-based OpenNebula VMs). Instead of the default Virtualbox hypervisor software, Vagrant uses KVM in order to allow nested virtualization (a VM running inside another VM) of 64-bit VMs.

## Pre-requisites
The 2 hypervisor VMs could potentially run multiple OpenNebula VMs within them. This needs adequate CPU cores and memory on the test server. Representative values are included in the Vagrantfile. Using these values will require a 2.5GB RAM and 5 CPU cores just to run the Front-end (512MB RAM and 1 CPU core) and two hypervisors (1GB RAM and 2 CPU cores each). Also, the test server should be running a Linux kernel > 3.16.0.34 (e.g. 3.19.X) for KVM nested virtualization to work correctly.

## Installation

Steps for installing the Vagrant OpenNebula developer environment on the test server is described below. This procedure was tested on an Ubuntu 14.04 test server, with a Linux  3.19.0-25 SMP kernel. For Ubuntu, a newer kernel can be installed (Kernels < 3.16.0-34 may not work).
```bash
apt-cache search linux-image
apt-get install linux-image-3.19.0-25
```

1.[Install](http://docs.vagrantup.com/v2/installation/index.html) Vagrant
2. Install [libvirt](http://libvirt.org/) on the host operating System
3. [Install](https://github.com/pradels/vagrant-libvirt) the Vagrant libvirt extension `vagrant-libvirt`
4. The next step is to get a Vagrant libvirt KVM Ubuntu image. Look at the [vagrant-mutate](https://github.com/sciurus/vagrant-mutate) project to convert a virtualbox Vagrant box to libvirt. Or, a pre-tested libvirt vagrant box to use is available from [here](https://vagrantcloud.com/naelyn/boxes/ubuntu-trusty64-libvirt). For this example we will install and use this ready-made box. To install, run
```bash
vagrant box add naelyn/ubuntu-trusty64-libvirt
```
5. Now we are ready to run the `preparenfs.sh` script. This will setup NFS mount points for the shared datastore required by OpenNebula and a shared folder (`/sharedstuff`) between the 3 VMs as well.
```bash
sudo ./preparenfs.sh
```
If you have run `preparenfs.sh` before there may be a warning about duplicate NFS mountpoints in the `/etc/exports` file. This file can be edited to remove duplicate entries.
6.  Next we bring up the Front-end and 2 hypervisors. These VMs are defined in `Vagrantfile`. This will do a "base setup" of the VMs.
``` bash
vagrant up onefrontend --provider libvirt
vagrant up hypervisor1 --provider libvirt
vagrant up hypervisor2 --provider libvirt
```
7. Next, each of the VMs needs to be "customized" using the scripts in the `/sharedstuff` directory in each VM.
  1. Log into the onefrontend VM and run this command

  ```bash
  vagrant ssh onefrontend #To SSH from the host
  cd /sharedstuff #In onefrontend
  sudo ./onefrontend.sh
  ```
  (_NOTE: There will be 3 prompts during OpenNebula installation that require keyboard user inputs_).
  This will install the OpenNebula onefrontend in the VM (See details about [OpenNebula installation](http://docs.opennebula.org/4.12/design_and_installation/building_your_cloud/ignc.html) here if you want to understand what the script does and correct any errors you may encounter).
  2. Log into each of the hypervisors and run these commands

  ```bash
  vagrant ssh hypervisor<1 or 2> #To SSH from the host
  cd /sharedstuff #In the hypervisor VM
  sudo ./hypervisor.sh
  ```
  This script will install KVM hypervisor software and setup Open Virtual Switch (ovs) bridge functionality on the hypervisors.

---
### Installation testing/Getting started
_All the commands below run under the oneadmin user account on the onefrontend: `sudo su - oneadmin`_
* Test if OpenNebula is correctly working
```bash
oneadmin@onefrontend:~$ onevm list m
    ID USER     GROUP    NAME            STAT UCPU    UMEM HOST             TIME
```
* Create a vnet
```bash
cat <<EOF > testvnet.tpl
NAME=testvnet
BRIDGE="onebridge"
DESCRIPTION="Native network"
GATEWAY="192.168.50.1"
NETWORK_ADDRESS="192.168.50.0"
NETWORK_MASK="255.255.255.0"
AR=[TYPE = "IP4", IP = "192.168.50.20", SIZE = "4" ]
EOF
oneadmin@onefrontend:~$ onevnet create testvnet.tpl
ID: 0
oneadmin@onefrontend:~$ onevnet list m
  ID USER            GROUP        NAME                CLUSTER    BRIDGE   LEASES
   0 oneadmin        oneadmin     testvnet            -          onebridg      0

   oneadmin@onefrontend:~$ onevnet show 0
   VIRTUAL NETWORK 0 INFORMATION
   ID             : 0
   NAME           : testvnet
   USER           : oneadmin
   GROUP          : oneadmin
   CLUSTER        : -
   BRIDGE         : onebridge
   VLAN           : No
   USED LEASES    : 0

   PERMISSIONS
   OWNER          : um-
   GROUP          : ---
   OTHER          : ---

   VIRTUAL NETWORK TEMPLATE
   BRIDGE="onebridge"
   DESCRIPTION="Native network"
   GATEWAY="192.168.50.1"
   NETWORK_ADDRESS="192.168.50.0"
   NETWORK_MASK="255.255.255.0"
   PHYDEV=""
   VLAN="NO"
   VLAN_ID=""

   ADDRESS RANGE POOL
    AR TYPE    SIZE LEASES               MAC              IP          GLOBAL_PREFIX
     0 IP4        4      0 02:00:c0:a8:32:14   192.168.50.20                      -

   LEASES
   AR  OWNER                    MAC              IP                      IP6_GLOBAL
```

* Import an image - The C12G labs' [OpenNebula marketplace](http://marketplace.c12g.com/appliance) is an excellent place to start importing a pre-built and OpenNebula-compatible image. There are dozens of images to choose from. For testing, download the [Ubuntu 14.04 KVM image](http://marketplace.c12g.com/appliance/53e7c1b28fb81d6a69000003) into the shared folder (/sharedstuff). This folder is recommended because the onefrontend VM has limited OS drive space, and the downloaded image may be useful for subsequent OpenNebula test-setups so there is no reason to download it into the OS-disk of the onefrontend VM that will get recycled once the vagrant environment is destroyed.
Get the image and create the template to import it unto the OpenNebula system.
```bash
oneadmin@onefrontend:/sharedstuff$ wget http://marketplace.c12g.com/appliance/53e7c1b28fb81d6a69000003/download/0
oneadmin@onefrontend:/sharedstuff$ mv 0 ubuntu1404.qcow2.gz
oneadmin@onefrontend:/sharedstuff$ gunzip ubuntu1404.qcow2.gz
cat << EOF > ubuntu1404.tpl
NAME = "Ubuntu 1404, 64 bit"
PATH = /sharedstuff/ubuntu1404.qcow2
DRIVER = qcow2
DESCRIPTION = "Ubuntu 14.04 image from the C12G website"
EOF
oneadmin@onefrontend:~$ onedatastore list
  ID NAME                SIZE AVAIL CLUSTER      IMAGES TYPE DS       TM
   0 system                0M -     -                 0 sys  -        shared
   1 default           105.4G 48%   -                 0 img  fs       shared
   2 files              39.3G 92%   -                 0 fil  fs       ssh
oneadmin@onefrontend:~$ oneimage create ubuntu1404.tpl --datastore 1
ID: 0
#After some time
oneadmin@onefrontend:~$ oneimage list m
  ID USER       GROUP      NAME            DATASTORE     SIZE TYPE PER STAT RVMS
   0 oneadmin   oneadmin   Ubuntu 1404, 64 default        10G OS    No rdy     0
```
* Claim the 2 hypervisors in the Front-end
```bash
vagrant@onefrontend:~$ sudo su - oneadmin
oneadmin@onefrontend:~$ onehost create 192.168.50.17 -i kvm -v kvm -n ovswitch
ID: 0
oneadmin@onefrontend:~$ onehost create 192.168.50.18 -i kvm -v kvm -n ovswitch
ID: 1
oneadmin@onefrontend:~$ onehost list
  ID NAME            CLUSTER   RVM      ALLOCATED_CPU      ALLOCATED_MEM STAT  
   0 192.168.50.17   -           0       0 / 300 (0%)       0K / 2G (0%) on
   1 192.168.50.18   -           0                  -                  - init
oneadmin@onefrontend:~$
```
* Test an OpenNebula VM lifecycle
  1. Create a VM template, _remember to paste the correct public key contents of the oneadmin user here under "SSH_PUBLIC_KEY". Yours will be different from the example shown below._:
  ```bash
  cat << EOF > testvm.tpl
  NAME=UbuntuVM
CONTEXT=[
	NETWORK="YES",
	SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDXWn+9zi2kEL0rnj/4W+pqec2zbdQl3SYjirlR4wloSL22GeOlbR6IU0XmwLkVuOphIfkXFdY1mIqWwkGKKY0pweedOjWVl8QcuB9vaKhOL2DOuiibeb+8irYj4lSmAcJakFZ8a3pxV3o/vnreG2idm5MgWcc+OlU6X0h4cl5sKnJwHf5fbQAAMTh8G3PxLTVgB7i9VEJL0jbZPbTubuP5jWiOfKHniB/OyW7sYxW67Z5sykcu+/X31roj+J2cbhrJuXU7g1DFKvK1X1ju5Fx05GzhTWIyJZ2GZZS/PxIkjBZQ5aV3ErbKp0OMWce7LwC+K17QpfAz4BtQe0TtnEiD oneadmin@onegeneric" ]
CPU="1"
DISK=[
	IMAGE_ID=0 ]
GRAPHICS=[
	LISTEN="0.0.0.0",
	TYPE="VNC"
	]
MEMORY="256"
NIC=[
	NETWORK_ID=0 ]
EOF
oneadmin@onefrontend:~$ onetemplate list m
  ID USER            GROUP           NAME                                REGTIME
   0 oneadmin        oneadmin        UbuntuVM                     08/21 16:45:37
```

  2. Instantiate a VM

    ```bash
      oneadmin@onefrontend:~$ onetemplate instantiate 0 --name firstvm VM ID: 0
    ```
     _After a few seconds_
     ```bash
     oneadmin@onefrontend:~$ onevm list m
     ID USER     GROUP    NAME            STAT UCPU    UMEM HOST             TIME      0 oneadmin oneadmin firstvm        runn    0      0K 192.168.50   0d 00h00 o
     oneadmin@onefrontend:~$ onevm show 1 | grep ETH0_IP
     ETH0_IP="192.168.50.20",
     oneadmin@onefrontend:~$ ssh -i ~/.ssh/id_rsa root@192.168.50.20
     Warning: Permanently added '192.168.50.20' (ECDSA) to the list of known hosts.
     Welcome to Ubuntu 14.04.1 LTS (GNU/Linux 3.13.0-32-generic x86_64)
    - Documentation:  https://help.ubuntu.com/

    root@ubuntu:~#
   ```

We now have a fully functioning 2-hypervisor Vagrant OpenNebula testbed. Refer to the excellent [OpenNebula Documentation](http://opennebula.org/documentation/) for further information.

---
