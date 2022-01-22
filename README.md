# hd-idle-assist

Bash script to assist hd-idle to make disks spin down

### Why?
Some disks spin up for S.M.A.R.T check by smartd without making any I/O, which makes hd-idle unable to tell if the disk is in active/idle or standby.
This script checks disk status using hdparm and make disk spin down if not in use.

### Required packages

- hdparm
- [hd-idle](https://github.com/adelolmo/hd-idle) (>v1.13) with debug option on

### Note

- This script checks syslog of hd-idle **with debug option**. Make sure to **use hd-idle from the link, not from distros' repository**
- Only /dev/sdc & /dev/sdd disks are checked. Edit script based on your system
