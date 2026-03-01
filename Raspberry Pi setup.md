
# OS choice

TODO

# Setup


## DietPi config


### cmdline.txt
```
root=PARTUUID=3db938b9-02 rootfstype=ext4 rootwait fsck.repair=yes net.ifnames=0 logo.nologo console=tty1 usbcore.autosuspend=-1
```

Removed extra console and disabled the power saving USB feature 
### config.txt changes
```
max_framebuffers=0
gpu_mem=16
disable_splash=1
enable_uart=0
dtoverlay=disable-wifi
dtoverlay=disable-bt
dtoverlay=vc4-kms-v3d,no-display
```

As I am low on resources, I disabled all of the extras I won't need, like display and serial console. Bluetooth would be nice to setup as a Bluetooth proxy for my Proxmox Home Assistant VM, but as the Pi is a backup and monitoring box, I would rather conserve my resources and use a different server with Bluetooth capabilities.
### Automation_Custom_Script.sh
```sh
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
```

As far as I know TRIM is not enabled by default which is needed to juggle around files inside of the external SSD I am adding to my Pi. Without TRIM some parts of the NAND chips will wear down sooner than others. TRIM makes it so when information is written or erased other data is juggled around to wear all of the NAND chips equally. Python will be used for Ansible automations, where the Pi is the end client and not the one running Ansible Workbooks. Also explicitly tell to not fill up the SSD with Docker logs. Ideally Docker would be installed already and the script would be ran after.

### dietpi.txt
```
CONFIG_ENABLE_IPV6=0
AUTO_SETUP_INSTALL_SOFTWARE_ID=134 130
AUTO_SETUP_BOOT_WAIT_FOR_NETWORK=1
CONFIG_SERIAL_CONSOLE_ENABLE=0
SOFTWARE_DISABLE_SSH_PASSWORD_LOGINS=root
AUTO_SETUP_SSH_PUBKEY=ssh-ed25519 .....
AUTO_UNMASK_LOGIND=1
CONFIG_CHECK_APT_UPDATES=1
AUTO_SETUP_GLOBAL_PASSWORD=......
AUTO_SETUP_AUTOMATED=1
AUTO_SETUP_HEADLESS=1
AUTO_SETUP_NET_USESTATIC=1
AUTO_SETUP_NET_STATIC_IP=Pi_ip
AUTO_SETUP_NET_STATIC_MASK=255.255.0.0
AUTO_SETUP_NET_STATIC_GATEWAY=Router_ip
AUTO_SETUP_NET_STATIC_DNS=1.1.1.1 9.9.9.9
AUTO_SETUP_NET_HOSTNAME=Igors
AUTO_SETUP_SWAPFILE_LOCATION=zram
AUTO_SETUP_SWAPFILE_SIZE=1
AUTO_SETUP_TIMEZONE=Europe/Riga
AUTO_SETUP_LOGGING_INDEX=-2
AUTO_SETUP_RAMLOG_MAXSIZE=100
```

TODO explain


![](attachments/Pasted%20image%2020260301025337.png)
As a result when trying to connect to the device it runs well and even shows that it is setting up!

Also setting up Bitwarden SSH keys gives everything a premium feeling, because the ssh keys are protected with an extra layer of protection and can be used with other computers that you have set up with Bitwarden.


### Troubleshooting

So i checked if the USB to SATA SSD was properly initialized and gives TRIM (DISCARD) commands to the SATA SSD controller. It seems that for safety purposes the command wasn't sent.

```bash
root@Igors:~# lsblk -d -o NAME,DISC-ALN,DISC-GRAN,DISC-MAX,DISC-ZERO
NAME  DISC-ALN DISC-GRAN DISC-MAX DISC-ZERO
sda          0        0B       0B         0
zram0        0        4K       2T         0
```
So first I have to find if the USB device itself supports giving those commands
```bash
root@Igors:~# lsusb -t
/:  Bus 001.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/1p, 480M
    |__ Port 001: Dev 002, If 0, Class=Hub, Driver=hub/4p, 480M
/:  Bus 002.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/4p, 5000M
    |__ Port 002: Dev 002, If 0, Class=Mass Storage, Driver=uas, 5000M
```
It seems that the driver is correct and should give me all the details, now I need the product and vendor id to change it so the system runs in less compatible but more functional system that would allow TRIM commands. I need the line ``ID 174c:55aa`` where Vendor ID is 174c and product ID is 55aa.
```bash
root@Igors:~# lsusb
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 001 Device 002: ID 2109:3431 VIA Labs, Inc. Hub
Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 002 Device 002: ID 174c:55aa ASMedia Technology Inc. ASM1051E SATA 6Gb/s bridge, ASM1053E SATA 6Gb/s bridge, ASM1153 SATA 3Gb/s bridge, ASM1153E SATA 6Gb/s bridge
root@Igors:~# nano /etc/udev/rules.d/10-trim.rules
```
In the trim file we use those ID's and make the drive run in scsi_disk mode, thus getting full access to the drive:
```
ACTION=="add|change", ATTRS{idVendor}=="174c", ATTRS{idProduct}=="55aa", SUBSYSTEM=="scsi_disk", ATTR{provisioning_mode}="unmap"
```
Reloading the rules so that a restart is not needed and checking if TRIM is enabled. It is!
```
root@Igors:~# udevadm control --reload-rules && udevadm trigger
root@Igors:~# lsblk -d -o NAME,DISC-ALN,DISC-GRAN,DISC-MAX,DISC-ZERO
NAME  DISC-ALN DISC-GRAN DISC-MAX DISC-ZERO
sda          0        4K       4G         0
zram0        0        4K       2T         0
```
Running a manual TRIM shows that in my original RPI server setup I never did a TRIM on this drive as it was fully written at least once and still had data written on it.
```
root@Igors:~# fstrim -v /
/: 456.3 GiB (489974616064 bytes) trimmed
```
As I did set up the TRIM to run on a schedule in the DietPi config script, I don't need to set anything more up
```
root@Igors:~# systemctl status fstrim.timer
● fstrim.timer - Discard unused filesystem blocks once a week
     Loaded: loaded (/usr/lib/systemd/system/fstrim.timer; enabled; preset: enabled)
     Active: active (waiting) since Sun 2026-02-22 06:45:13 EET; 1 week 0 days ago
 Invocation: 1315e17951aa4575a50ac06e4d544489
    Trigger: Mon 2026-03-02 00:45:01 EET; 1h 10min left
   Triggers: ● fstrim.service
       Docs: man:fstrim

Feb 22 06:45:13 DietPi systemd[1]: Started fstrim.timer - Discard unused filesystem blocks once a week.
```
But as I did have TRIM disabled, it would be wise to check up on drive health
```
root@Igors:~# apt update && apt install smartmontools -y
root@Igors:~# smartctl -a /dev/sda
smartctl 7.4 2023-08-01 r5530 [aarch64-linux-6.12.62+rpt-rpi-v8] (local build)
Copyright (C) 2002-23, Bruce Allen, Christian Franke, www.smartmontools.org

=== START OF INFORMATION SECTION ===
Model Family:     Crucial/Micron Client SSDs
Device Model:     CT500MX500SSD1
Serial Number:    2212REDACTED
LU WWN Device Id: 5 00a075 1e6200965
Firmware Version: M3CR043
User Capacity:    500,107,862,016 bytes [500 GB]
Sector Sizes:     512 bytes logical, 4096 bytes physical
Rotation Rate:    Solid State Device
Form Factor:      2.5 inches
TRIM Command:     Available
Device is:        In smartctl database 7.3/5528
ATA Version is:   ACS-3 T13/2161-D revision 5
SATA Version is:  SATA 3.3, 6.0 Gb/s (current: 6.0 Gb/s)
Local Time is:    Sun Mar  1 23:36:17 2026 EET
SMART support is: Available - device has SMART capability.
SMART support is: Enabled

=== START OF READ SMART DATA SECTION ===
SMART overall-health self-assessment test result: PASSED

General SMART Values:
Offline data collection status:  (0x80) Offline data collection activity
                                        was never started.
                                        Auto Offline Data Collection: Enabled.
Self-test execution status:      (   0) The previous self-test routine completed
                                        without error or no self-test has ever 
                                        been run.
Total time to complete Offline 
data collection:                (    0) seconds.
Offline data collection
capabilities:                    (0x7b) SMART execute Offline immediate.
                                        Auto Offline data collection on/off support.
                                        Suspend Offline collection upon new
                                        command.
                                        Offline surface scan supported.
                                        Self-test supported.
                                        Conveyance Self-test supported.
                                        Selective Self-test supported.
SMART capabilities:            (0x0003) Saves SMART data before entering
                                        power-saving mode.
                                        Supports SMART auto save timer.
Error logging capability:        (0x01) Error logging supported.
                                        General Purpose Logging supported.
Short self-test routine 
recommended polling time:        (   2) minutes.
Extended self-test routine
recommended polling time:        (  30) minutes.
Conveyance self-test routine
recommended polling time:        (   2) minutes.
SCT capabilities:              (0x0031) SCT Status supported.
                                        SCT Feature Control supported.
                                        SCT Data Table supported.

SMART Attributes Data Structure revision number: 16
Vendor Specific SMART Attributes with Thresholds:
ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
  1 Raw_Read_Error_Rate     0x002f   100   100   000    Pre-fail  Always       -       0
  5 Reallocate_NAND_Blk_Cnt 0x0032   100   100   010    Old_age   Always       -       0
  9 Power_On_Hours          0x0032   100   100   000    Old_age   Always       -       26
 12 Power_Cycle_Count       0x0032   100   100   000    Old_age   Always       -       9
171 Program_Fail_Count      0x0032   100   100   000    Old_age   Always       -       0
172 Erase_Fail_Count        0x0032   100   100   000    Old_age   Always       -       0
173 Ave_Block-Erase_Count   0x0032   100   100   000    Old_age   Always       -       2
174 Unexpect_Power_Loss_Ct  0x0032   100   100   000    Old_age   Always       -       3
180 Unused_Reserve_NAND_Blk 0x0033   000   000   000    Pre-fail  Always       -       60
183 SATA_Interfac_Downshift 0x0032   100   100   000    Old_age   Always       -       0
184 Error_Correction_Count  0x0032   100   100   000    Old_age   Always       -       0
187 Reported_Uncorrect      0x0032   100   100   000    Old_age   Always       -       0
194 Temperature_Celsius     0x0022   067   053   000    Old_age   Always       -       33 (Min/Max 0/47)
196 Reallocated_Event_Count 0x0032   100   100   000    Old_age   Always       -       0
197 Current_Pending_ECC_Cnt 0x0032   100   100   000    Old_age   Always       -       0
198 Offline_Uncorrectable   0x0030   100   100   000    Old_age   Offline      -       0
199 UDMA_CRC_Error_Count    0x0032   100   100   000    Old_age   Always       -       0
202 Percent_Lifetime_Remain 0x0030   100   100   001    Old_age   Offline      -       0
206 Write_Error_Rate        0x000e   100   100   000    Old_age   Always       -       0
210 Success_RAIN_Recov_Cnt  0x0032   100   100   000    Old_age   Always       -       0
246 Total_LBAs_Written      0x0032   100   100   000    Old_age   Always       -       861228380
247 Host_Program_Page_Count 0x0032   100   100   000    Old_age   Always       -       9578388
248 FTL_Program_Page_Count  0x0032   100   100   000    Old_age   Always       -       6891776

SMART Error Log Version: 1
No Errors Logged

SMART Self-test log structure revision number 1
No self-tests have been logged.  [To run self-tests, use: smartctl -t]

SMART Selective self-test log data structure revision number 1
 SPAN  MIN_LBA  MAX_LBA  CURRENT_TEST_STATUS
    1        0        0  Not_testing
    2        0        0  Not_testing
    3        0        0  Not_testing
    4        0        0  Not_testing
    5        0        0  Completed [00% left] (0-65535)
Selective self-test flags (0x0):
  After scanning selected spans, do NOT read-scan remainder of disk.
If Selective self-test is pending on power-up, resume after 0 minute delay.

The above only provides legacy SMART information - try 'smartctl -x' for more

```
The drive seems hardly used, so I might have used this drive for an SMB share or some test instead of an RPI drive. 
```
root@Igors:~# smartctl -t short /dev/sda
smartctl 7.4 2023-08-01 r5530 [aarch64-linux-6.12.62+rpt-rpi-v8] (local build)
Copyright (C) 2002-23, Bruce Allen, Christian Franke, www.smartmontools.org

=== START OF OFFLINE IMMEDIATE AND SELF-TEST SECTION ===
Sending command: "Execute SMART Short self-test routine immediately in off-line mode".
Drive command "Execute SMART Short self-test routine immediately in off-line mode" successful.
Testing has begun.
Please wait 2 minutes for test to complete.
Test will complete after Sun Mar  1 23:40:28 2026 EET
Use smartctl -X to abort test.

```