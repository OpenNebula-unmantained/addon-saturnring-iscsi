#!/bin/bash

#Setup NFS
apt-get install nfs-kernel-server nfs-common rpcbind
mkdir -p ontestbed
mkdir -p ontestbed/oneds0
mkdir -p ontestbed/oneds1
mkdir -p ontestbed/onedbfolder

PWD=`pwd`
chown -R 9869:9869  ${PWD}/ontestbed #This is the UID and GID of the oneadmin user, created by the OpenNebula installer.
chown -R 9869:9869 ${PWD}/sharedstuff

cat <<EOF >> /etc/exports
$PWD/ontestbed/oneds0 *(rw,no_root_squash,no_subtree_check)
$PWD/ontestbed/oneds1 *(rw,no_root_squash,no_subtree_check)
$PWD/ontestbed/onedbfolder *(rw,no_root_squash,no_subtree_check)
$PWD/sharedstuff *(rw,no_root_squash,no_subtree_check)
EOF

#ONEGENERIC
cat <<EOF > ./sharedstuff/onegeneric.sh
#!/bin/bash
apt-get update
apt-get install nfs-common -y
mkdir -p /sharedstuff
NFSIPPREFIX=\$(ifconfig eth0 | awk '/inet / { print \$2 }' | sed 's/addr://' | cut -d . -f4 --complement)
cat <<EF >> /etc/fstab
\$NFSIPPREFIX.1:$PWD/sharedstuff /sharedstuff nfs
EF
mount -a

EOF

#FRONTEND
cat <<EOF > ./sharedstuff/frontend.sh

#!/bin/bash

apt-get install ruby-dev sqlite3 -y 
gem install json
mv /usr/lib/ruby/1.9.1/json.rb /usr/lib/ruby/1.9.1/json.rb.no
echo "deb http://downloads.opennebula.org/repo/4.10/Ubuntu/14.04 stable opennebula" > /etc/apt/sources.list.d/opennebula.list
wget -q -O- http://downloads.opennebula.org/repo/Debian/repo.key | apt-key add -
apt-get update
apt-get install opennebula-sunstone opennebula -y

#Problem with automating this script: - Y and enter and y needed
/usr/share/one/install_gems


echo "Stopping one"
sudo -H -u oneadmin bash -c 'one stop'
echo "Creating some shared directories"
mkdir -p /onedbfolder
chown oneadmin:oneadmin /onedbfolder
mkdir -p /sharedstuff
chown -R oneadmin:oneadmin /sharedstuff
echo "Mounting nfs shares"
NFSIPPREFIX=\$(ifconfig eth0 | awk '/inet / { print \$2 }' | sed 's/addr://' | cut -d . -f4 --complement)
cat <<EF >> /etc/fstab
\$NFSIPPREFIX.1:$PWD/ontestbed/oneds0 /var/lib/one/datastores/0 nfs
\$NFSIPPREFIX.1:$PWD/ontestbed/oneds1 /var/lib/one/datastores/1 nfs
\$NFSIPPREFIX.1:$PWD/ontestbed/onedbfolder /onedbfolder nfs
EF
mount -a
echo "SSH keys"
cp /sharedstuff/sshkeys.tar.gz /var/lib/one
chown oneadmin:oneadmin /var/lib/one/sshkeys.tar.gz
sudo -H -u oneadmin bash -c 'cd /var/lib/one; tar -xvzf sshkeys.tar.gz'

#one start
echo "Starting one"
sudo -H -u oneadmin bash -c 'one start'
echo "Done!"
exit 0


EOF
chmod +x ./sharedstuff/frontend.sh

#HYPERVISOR
cat <<EOF > ./sharedstuff/hypervisor.sh

#!/bin/bash
echo "deb http://downloads.opennebula.org/repo/4.10/Ubuntu/14.04 stable opennebula" > /etc/apt/sources.list.d/opennebula.list
wget -q -O- http://downloads.opennebula.org/repo/Debian/repo.key | apt-key add -
apt-get update
apt-get install opennebula-node bridge-utils -y

apt-get install open-iscsi openvswitch-switch -y
RANDOM=`date +%s`$$
cat <<EF > /etc/iscsi/initiatorname.iscsi
InitiatorName=iqn.iscsihypervisor${RANDOM}${RANDOM}.ini
EF
service open-iscsi restart

NFSIPPREFIX=\$(ifconfig eth0 | awk '/inet / { print \$2 }' | sed 's/addr://' | cut -d . -f4 --complement)
mkdir -p /var/lib/one/datastores/0
chown oneadmin:oneadmin /var/lib/one/datastores/0
mkdir -p /var/lib/one/datastores/1
chown oneadmin:oneadmin /var/lib/one/datastores/1
cat <<EF >> /etc/fstab
\$NFSIPPREFIX.1:$PWD/ontestbed/oneds0 /var/lib/one/datastores/0 nfs
\$NFSIPPREFIX.1:$PWD/ontestbed/oneds1 /var/lib/one/datastores/1 nfs
EF
mount -a
echo "SSH keys"
cp /sharedstuff/sshkeys.tar.gz /var/lib/one
chown oneadmin:oneadmin /var/lib/one/sshkeys.tar.gz
sudo -H -u oneadmin bash -c 'cd /var/lib/one; tar -xvzf sshkeys.tar.gz'

#OVS configuration - assumes eth1 has to be reassigned to the bridge
#Assume /24
#Assume gateway is at .1
PHYDEV="eth1"
ovs-vsctl add-br onebridge
ifconfig onebridge up
IPADDR=\$(ifconfig \${PHYDEV} | awk '/inet / { print \$2 }' | sed 's/addr://')
GWPREFIX=\$(ifconfig \${PHYDEV} | awk '/inet / { print \$2 }' | sed 's/addr://' | cut -d . -f4 --complement)
ip addr del \${IPADDR}/24 dev \${PHYDEV}
ovs-vsctl add-port onebridge \${PHYDEV}
ifconfig onebridge \${IPADDR} netmask 255.255.255.0
ifconfig \${PHYDEV} 0
route del default
route add default gw \${GWPREFIX}.1 dev onebridge

EOF


exportfs -ra
service nfs-kernel-server restart


