#!/bin/bash

#------------------------------------------------------------------
#
# hd-idle-assist
# Created on 2022 Jan 21
# Author: TheNoFace (thenoface303@gmail.com)
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
	local status=$(hdparm -C /dev/$1 | awk 'FNR == 3 {print $4}')

	if [[ "${status}" != 'standby' ]]
	then
		return 1
	fi
}

function spin_check()
{
	local status=$(tac /var/log/syslog | grep $1 -m 1 | grep -oP 'spunDown=\K[^ ]+')

	case "${status}" in
		'true'|'false')
			if [[ "${status}" != 'true' ]]
			then
				return 1
			else
				return 0
			fi ;;
		*)
			msg "WARNING: Wrong status for [$1](${status})"
			logError=1
	esac

	if [[ ${logError} != 0 ]]
	then
		if [[ ${i} -lt 10 ]]
		then
			msg "Recheck hd-idle log in 30 seconds..."
			sleep 30
			((i++))
			unset logError
			spin_check $1
		else
			msg "ERROR: hd-idle log recheck failed!"
			exit 10
		fi
	fi
	unset i
}

function into_idle()
{
	msg "Spinning down [$1]..."
	hd-idle -t /dev/$1
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
	unset activeList spinList inTest anomalStatus
	for i in ${diskList[@]}
	do
		is_active ${i}
		isActive=$?
		if [[ ${isActive} != 0 ]]
		then
			activeList=(${activeList[@]} ${i})
		fi
	done

	if ! is_empty ${activeList[@]}
	then
		for i in ${diskList[@]}
		do
			smartctl_check ${i}
			returnCode=$?
			if [[ ${returnCode} != 0 ]]
			then
				inTest=(${inTest[@]} ${i})
			fi
		done

		if ! is_empty ${inTest[@]}
		then
			msg "Disk(s) under smartctl self-test: [${inTest[@]}], re-check in ${recheckInt} seconds"
			sleep ${recheckInt}
			main
		fi

		for i in ${diskList[@]}
		do
			spin_check ${i}
			isSpin=$?
			if [[ ${isSpin} != 0 ]]
			then
				spinList=(${spinList[@]} ${i})
			fi
		done

		if [[ "${activeList[@]}" != "${spinList[@]}" ]]
		then
			# https://stackoverflow.com/a/16861932
			anomalStatus=("${activeList[@]}")
			for del in ${spinList[@]}
			do
				anomalStatus=(${anomalStatus[@]/${del}})
			done

			if is_empty ${isRecheck}
			then
				msg "Disk in idle queue: [${anomalStatus[@]}], re-check disk status in ${recheckInt} seconds"
				sleep ${recheckInt}
				isRecheck=1
				main
			elif ! is_empty ${isRecheck}
			then
				msg "Disk in idle queue: [${anomalStatus[@]}]"
				for idle in ${anomalStatus[@]}
				do
					into_idle $idle
				done
			else
				msg "ERROR: Unknown status for isRecheck(${isRecheck})"
				exit 20
			fi
			unset activeList spinList anomalStatus isRecheck
		elif [[ "${activeList[@]}" = "${spinList[@]}" ]]
		then
			msg "hd-idle is waiting for disk [${spinList[@]}] to spindown, re-check in ${recheckInt} seconds"
			sleep ${recheckInt}
		fi

		main # loop
		msg "ERROR: Exit 21" && exit 21 # wrong exit
	elif is_empty ${activeList[@]}
	then
		msg "No active disk found"
		sleep ${refreshInt}
		main # loop
		msg "ERROR: Exit 22" && exit 22 # wrong exit
	fi
}

ulimit -s unlimited
msg "Stack size set to $(ulimit -s)"

msg "Disk to check: [${diskList[@]}], refresing every ${refreshInt}s"
main
msg "ERROR: EOF"
exit 255
