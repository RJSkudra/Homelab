#!/bin/bash

# Create the udev rule for the ASMedia bridge to enable TRIM (unmap)
echo 'ACTION=="add|change", ATTRS{idVendor}=="174c", ATTRS{idProduct}=="55aa", SUBSYSTEM=="scsi_disk", ATTR{provisioning_mode}="unmap"' > /etc/udev/rules.d/10-trim.rules

# Reload udev to apply the rule immediately
udevadm control --reload-rules && udevadm trigger

# Enable the systemd timer to run fstrim weekly
systemctl enable fstrim.timer
systemctl start fstrim.timer

# Force TRIM on boot
fstrim -v /

# Backup python3 install for Ansible in case DietPie fails to install it
apt-get update
apt-get install -y python3 python3-pip

# Set global Docker log rotation (Max 3 files of 10MB each)
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker