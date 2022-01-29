#!/bin/bash

#------------------------------------------------------------------
#
# hd-idle-assist
# Created on 2022 Jan 21
# Author: TheNoFace (thenoface303@gmail.com)
# Version 1.0.2
#
#------------------------------------------------------------------

[[ $(id -u) != 0 ]] && echo "Do sudo!" && exit 255

if [ -z $1 ]
then
	refreshInt=60
else
	refreshInt=$1
fi

recheckInt=300 # Recheck after 5 minutes

function msg()
{
	echo -e "[$(date +'%F %T')] $1"
}

function is_active()
{
	sdcStatus=$(hdparm -C /dev/sdc | awk 'FNR == 3 {print $4}')
	sddStatus=$(hdparm -C /dev/sdd | awk 'FNR == 3 {print $4}')
	msg "hdparm sdc: ${sdcStatus} / sdd: ${sddStatus}"

	if [[ "${sdcStatus}" != 'standby' ]] || [[ "${sddStatus}" != 'standby' ]]
	then
		isActive=1
	else
		unset isActive
	fi
}

function spin_check()
{
	sdcLog=$(tac /var/log/syslog | grep "sdc" -m 1)
	sddLog=$(tac /var/log/syslog | grep "sdd" -m 1)

	sdcLength=$(echo ${sdcLog} | wc -m)
	sddLength=$(echo ${sddLog} | wc -m)

	# hd-idle init: 252 | spinup/down: 55/53 | default: about 220
	if [[ ${sdcLength} -gt 240 ]] || [[ ${sddLength} -gt 240 ]]
	then
		msg "sdcLength: ${sdcLength} / sddLength: ${sddLength}"
		msg "Wrong log, re-check in 60 seconds"
		sleep 60
		spin_check
	fi

	sdcSpinDown=$(tac /var/log/syslog | grep "sdc" -m 1 | grep -oP 'spunDown=\K[^ ]+')
	sddSpinDown=$(tac /var/log/syslog | grep "sdd" -m 1 | grep -oP 'spunDown=\K[^ ]+')
	msg "hd-idle spundown sdc: ${sdcSpinDown} / sdd: ${sddSpinDown}"
}

main()
{
	is_active
	if [[ ! -z ${isActive} ]]
	then
		msg "Found active disk!"
		spin_check
		if [[ ${sdcSpinDown} == 'false' ]] || [[ ${sddSpinDown} == 'false' ]]
		then
			msg "hd-idle is still waiting for disk(s) to spindown, re-check in ${recheckInt} seconds"
			sleep ${recheckInt}
			main
		fi

		if [[ ${sdcStatus} != 'standby' ]] || [[ ${sddStatus} != 'standby' ]]
		then
			msg "hd-idle didn't recognize disk spinup, re-check disk status in ${recheckInt} seconds"
			sleep ${recheckInt}
			is_active
			spin_check
		fi

		if [[ ${sdcStatus} != 'standby' ]] && [[ ${sdcSpinDown} == 'true' ]]
		then
			msg "Spinning down sdc..."
			hd-idle -t /dev/sdc
		fi

		if [[ ${sddStatus} != 'standby' ]] && [[ ${sddSpinDown} == 'true' ]]
		then
			msg "Spinning down sdd..."
			hd-idle -t /dev/sdd
		fi

		main # loop
		exit 11 # wrong exit
	elif [[ -z ${isActive} ]]
	then
		sleep 60
		main # loop
		exit 12 #wrong exit
	else
		msg "ERROR: Unknown disk state sdc: ${sdcStatus} / sdd: ${sddStatus}"
		exit 1
	fi
}

msg "Refresing every ${refreshInt}s"
main
msg "ERROR: EOF"
exit 10
