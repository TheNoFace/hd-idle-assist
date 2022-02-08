#!/bin/bash

#------------------------------------------------------------------
#
# hd-idle-assist
# Created on 2022 Jan 21
# Author: TheNoFace (thenoface303@gmail.com)
# Version 1.0.3
#
# TODO
# 1. Get user-defined disklist as an argunmet, not pre-defined ones
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
diskList=(sdc sdd)

function msg()
{
	echo "[$(date +'%F %T')] $*"
}

function is_empty()
{
	[[ -z "${1}" ]] && return 0
	return 1
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
	sdcSpinDown=$(tac /var/log/syslog | grep "sdc" -m 1 | grep -oP 'spunDown=\K[^ ]+')
	sddSpinDown=$(tac /var/log/syslog | grep "sdd" -m 1 | grep -oP 'spunDown=\K[^ ]+')

	case "${sdcSpinDown}" in
		'true'|'false')
			;;
		*)
			msg "WARNING: Wrong status for sdc: ${sdcSpinDown}"
			((logError++))
	esac

	case "${sddSpinDown}" in
		'true'|'false')
			;;
		*)
			msg "WARNING: Wrong status for sdd: ${sddSpinDown}"
			((logError++))
	esac

	if [[ ! -z ${logError} ]]
	then
		if [[ ${i} -lt 10 ]]
		then
			msg "Recheck hd-idle log in 10 seconds..."
			sleep 10
			((i++))
			unset logError
			spin_check
		else
			msg "ERROR: hd-idle log recheck failed!"
			exit 13
		fi
	fi

	msg "hd-idle spundown sdc: ${sdcSpinDown} / sdd: ${sddSpinDown}"
	unset i
}

function smartctl_check()
{
	local status=$(smartctl -c /dev/${1} | grep 'Self-test routine in progress...')
	if ! is_empty "${status}"
	then
		return 1
	fi
}

main()
{
	is_active
	if [[ ! -z ${isActive} ]]
	then
		msg "Found active disk!"

		for i in ${diskList[@]}
		do
			smartctl_check ${i}
			returnCode=$?
			if [[ ${returnCode} != 0 ]]
			then
				nowTesting=(${nowTesting[@]} ${i})
				((smartTest++))
			fi
		done

		if ! is_empty ${smartTest}
		then
			msg "Disk(s) under smartctl self-test: ${nowTesting[@]}, re-check in ${recheckInt} seconds"
			sleep ${recheckInt}
			unset nowTesting smartTest
			main
		fi

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
		exit 12 # wrong exit
	else
		msg "ERROR: Unknown disk state sdc: ${sdcStatus} / sdd: ${sddStatus}"
		exit 1
	fi
}

msg "Refresing every ${refreshInt}s"
main
msg "ERROR: EOF"
exit 10
