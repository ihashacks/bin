#!/bin/bash
#----------------------------------------------------------
# Name          : serverVCB.sh
# Author        : Michael Dixon
# Creation Date : 20090717
#----------------------------------------------------------
# Purpose:
#    Performs backup tasks on VMware Server (Linux Host)
#    virtual machines. 
#    Machines may be backed up "live", or
#    powered down and back up by this script. 
#----------------------------------------------------------
# Input:
#    This script requires an input file containing
#    a list of virtual machines to be backed up.
#    The format of this file is one line per machine
#    with each line containing the NAME of the VM
#----------------------------------------------------------
# Preparation:
#    Certain variables may be set in this script to
#    control it's behaviour.  Please read the comments
#    of these settings to determine if you want to set
#    these or not.
#----------------------------------------------------------
# Kudos:
#    Based on the original ghettoVCB ESX(i) script 
#    by William Lam
#----------------------------------------------------------
# History
# Ver  Date      Author   Description
# 1.0  20090717  Michael  Created
# 1.1  20090717  Michael  Fixed copy process with spaces
# 1.2  20090723  Michael  Added more friendly message when
#                         VM name does not match. Added
#                         summary counts to show how many
#                         backups succeded/failed
# 1.3  20090725  Michael  Modified getVimVar function to
#                         use " = " as the field seperator
#                         instead of a single space. This 
#                         allows values that contain spaces
#                         to be assigned correctly 
#----------------------------------------------------------
shopt -s extglob

#----------------------------------------------------------
# VMware authentication
#----------------------------------------------------------
# If a user and password is required enter one or both here
# In some cases neither is required
# In other cases supplying only the VM_USER is sufficient
# In yet other cases both must be specified
#----------------------------------------------------------
VM_USER=vmware
VM_PASSWORD=

#----------------------------------------------------------
# Archiving
#----------------------------------------------------------
# Set this to 1 to archive the vm backup with bzip2 or gzip
# Turning this on will issue the appropriate tar command 
# after the backup has been taken. Once the archive has 
# been created the backup files are then removed to recover
# the space. Enabling this can reduce the backup footprint 
# but the tradeoff is how long it takes to compress
#----------------------------------------------------------
ENABLE_ARCHIVING=0

#----------------------------------------------------------
# Backup location
#----------------------------------------------------------
# The directory that all VM backups will go. This location
# should obviously have enough space to copy your VM to
#----------------------------------------------------------
VM_BACKUP_VOLUME=/mnt/temp/backup

#----------------------------------------------------------
# Retention count
#----------------------------------------------------------
# Number of backups for a given VM to keep. This tells the
# script to keep the most recent "X" number of backups for
# each VM.
#----------------------------------------------------------
VM_BACKUP_ROTATION_COUNT=3

#----------------------------------------------------------
# Directory naming convention for backup rotations
#----------------------------------------------------------
# The default of "date +%F" here will create backup dirs
# for your VM backup with a suffix of YYYY-MM-DD
#----------------------------------------------------------
VM_BACKUP_DIR_NAMING_CONVENTION="$(date +%F)" 

#----------------------------------------------------------
# Shutdown guestOS prior to running backups?
#----------------------------------------------------------
# This feature assumes VMware Tools are installed, else the
# VM will not power down correctly and appear to hang.
# To prevent this you should enable Hard Power Off as well.
#----------------------------------------------------------
POWER_VM_DOWN_BEFORE_BACKUP=0

#----------------------------------------------------------
# Hit the "Power Switch" if the GuestOS Shutdown hangs?
#----------------------------------------------------------
ENABLE_HARD_POWER_OFF=1

#----------------------------------------------------------
# Power Switch Timer
#----------------------------------------------------------
# This is the number of time we check if the Guest OS has 
# shut down before we issue a hard power off. The number 
# specified here is multiplied by 3 to get the number of 
# seconds before going to a hard reset. "4" is the default, 
# which means that if the Guest shutdown hasn't powered off 
# the VM after 12 seconds then hit the "Power" switch.
#----------------------------------------------------------
ITER_TO_WAIT_SHUTDOWN=4
#----------------------------------------------------------
# This setting only comes into effect if both 
# POWER_VM_DOWN_BEFORE_BACKUP and ENABLE_HARD_POWER_OFF are 
# turned on above
#----------------------------------------------------------

#----------------------------------------------------------
# >>> DO NOT MODIFY BELOW THIS LINE <<<
#----------------------------------------------------------

#----------------------------------------------------------
# Debug Mode - set this to 1 for debugging output
DEBUG_MODE=0
# Internal Version
VERSION="1.3"
#----------------------------------------------------------

#----------------------------------------------------------
# Function: debugVar <STRING1> <STRING2>
# Purpose : Echo debugging info to console
#----------------------------------------------------------
debugVar() {
  if [ ${DEBUG_MODE} -eq 1 ]; then
	  echo -e "DEBUG: $1 = $2"
  fi
}

#----------------------------------------------------------
# Function: printUsage
# Purpose : Echo usage information to console
#----------------------------------------------------------
printUsage() {
	SCRIPT_PATH=$(basename $0)
	echo -e "\nUsage: ${SCRIPT_PATH} [VM_FILE_INPUT]\n"
}

#----------------------------------------------------------
# Function: getProduct
# Purpose : Determine which VMware product is being used
# Return  : productLineId variable
#----------------------------------------------------------
getProduct() {
  getVimVar "hostsvc/hostsummary" productLineId
}

#----------------------------------------------------------
# Function: getVimVar <COMMAND> <VARIABLE> <OPT:NEW_VAR>
# Purpose : Query VMware using <COMMAND> to extract the
#           value of <VARIABLE>.
# Return  : If <OPT:NEW_VAR> is not set then <VARIABLE>
#           will contain the required value. Otherise
#           <OPT:NEW_VAR> will contain the value
#----------------------------------------------------------
getVimVar() {
  debugVar "Searching $1 for" "$2"
  local CMD="${VMWARE_CMD} $1"
  ASSIGN_VAR=`eval $CMD | grep "$2" | awk -F " = " '{print $1 "=" $2}' | sed 's/,//g'`
  if [ "${ASSIGN_VAR}" != "" ]; then
    eval $ASSIGN_VAR
  fi
  if [ ! -z $3 ]; then
    debugVar "Alternate variable specified" "$3"
    ASSIGN_VAR="$3=\$$2"
    eval $ASSIGN_VAR
    unset $2
  fi
}

#----------------------------------------------------------
# Function: getSnapshotTasks
# Purpose : Get all Snapshot creation tasks for the
#           current VM
# Return  : SNAPSHOT_TASKS will contain 0 or more VMware
#           task references
#----------------------------------------------------------
getSnapshotTasks() {
  debugVar "Getting Snapshot Tasks for" "${VM_ID}"
  local ST_IFS=$IFS
  IFS=":"
  local CMD="${VMWARE_CMD} vmsvc/get.tasklist ${VM_ID}"
  SNAPSHOT_TASKS=`eval $CMD | grep createSnapshot | awk -F ":" '{print $2}' | sed s/"'"//g | sed 's/,//g'`
  IFS=$ST_IFS
}

#----------------------------------------------------------
# Function: getSnapshotStatus <SNAPSHOT_TASK>
# Purpose : Query the status of <SNAPSHOT_TASK>
# Return  : Variable "state" will contain status
#----------------------------------------------------------
getSnapshotStatus() {
  debugVar "Getting Snapshot State for" "$1"
  getVimVar "vimsvc/task_info $1" state
}

#----------------------------------------------------------
# Function: checkVMBackupRotation
# Purpose : Maintain VM_BACKUP_ROTATION_COUNT backups for
#           each VM
#----------------------------------------------------------
checkVMBackupRotation() {
  IFS=$'\012'
	local BACKUP_DIR_PATH=$1
	local BACKUP_VM_NAMING_CONVENTION=$2
	LIST_BACKUPS=$(ls -tr "${BACKUP_DIR_PATH}")

  debugVar "LIST_BACKUPS" "${LIST_BACKUPS}"

	#default rotation if variable is not defined
	if [ -z ${VM_BACKUP_ROTATION_COUNT} ]; then
		VM_BACKUP_ROTATION_COUNT=1
	fi
  debugVar "VM_BACKUP_ROTATION_COUNT" "${VM_BACKUP_ROTATION_COUNT}"
	
	for DIR in ${LIST_BACKUPS};
	do
	  debugVar "DIR" "${DIR}"
		TMP_DIR="${BACKUP_DIR_PATH}/${DIR}"
	  debugVar "TMP_DIR" "${TMP_DIR}"
		TMP=$(expr "${TMP_DIR}" : '.*\(--[0-9]*\)' | sed 's/-//g')
		TMP=${TMP:-0}
	  debugVar "TMP" "${TMP}"
	  debugVar "BACKUP_VM_NAMING_CONVENTION" "${BACKUP_VM_NAMING_CONVENTION}"
    if [ "${TMP}" = "${BACKUP_VM_NAMING_CONVENTION}" ]; then
      NEW="${TMP}--1"
      debugVar "Move newest" "$NEW"
      mv "${BACKUP_DIR_PATH}/${DIR}" "${NEW}"
    elif [ ${TMP} -ge ${VM_BACKUP_ROTATION_COUNT} ]; then
      debugVar "Remove old" "${BACKUP_DIR_PATH}/${DIR}"
      echo ">>>>>>>>>> Removing old backups..."
      rm -rf "${BACKUP_DIR_PATH}/${DIR}"
      echo ">>>>>>>>>> Done: Old backups removed"
    else
			BASE=$(echo "${TMP_DIR%--*}")
	    NEW=${BASE}--$((${TMP}+1))
	    debugVar "BASE" "$BASE"
	    debugVar "NEW" "$NEW"
	    debugVar "BACKUP_DIR_PATH + DIR" "${BACKUP_DIR_PATH}/${DIR}"
	    mv "${BACKUP_DIR_PATH}/${DIR}" "$NEW"
	  fi
	done	
	unset IFS
}

#----------------------------------------------------------
# Function: esxVmdkBackup
# Purpose : Placeholder to expand this script for ESX usage
#----------------------------------------------------------
esxVmdkBackup() {
  echo "This script has been tailored specifically for VMware Server 2"
  echo "Please see lamw's ESX(i) ghettoVCB script at http://communities.vmware.com/docs/DOC-8760"
}

#----------------------------------------------------------
# Function: gsxVmdkBackup
# Purpose : Backup virtual disks for the current VM when
#           the VM is running under VMware Server/GSX
#----------------------------------------------------------
gsxVmdkBackup() {
  IFS=":"
	echo ">>>>>>>>>> GSX: Backing up content of ${VM_NAME} ..."
  # Copy disks to backup location
  if [ ${RSYNC_FLAG} -eq 1 ]; then
    rsync -av --progress --exclude=*-000001*.vmdk ${VMX_DIR}/*.vmdk "${VM_BACKUP_DIR}/"
  else
    cp -p -v ${VMX_DIR}/!(*000001*|*.log|*.vmx*|*.vms*|*.vmem|*.nvram|*.lck) "${VM_BACKUP_DIR}/"
  fi
  # Take a copy of the VMX file to post-process
  VMX_BACKUP=${VM_BACKUP_DIR}/`basename ${VMX_PATH}`
  mv "${VMX_BACKUP}" "${VMX_BACKUP}.old"
	echo ">>>>>>>>>> GSX: Reconfiguring backup of ${VM_NAME} ..."
  # Point the VMX to the original disk instead of the snapshot
  sed '/fileName/s/-000001.vmdk/.vmdk/g' < "${VMX_BACKUP}.old" > "${VMX_BACKUP}"
  rm "${VMX_BACKUP}.old"
  unset IFS
  VM_COUNT_SUCCESS=$[ ${VM_COUNT_SUCCESS}+1 ]
}

#----------------------------------------------------------
# Function: archiveBackup
# Purpose : Create an archive of the current backup and
#           also remove the individual backup files to 
#           reclaim space
#----------------------------------------------------------
archiveBackup() {
  echo ">>>>>>>>>> Archiving the backup for ${VM_NAME}..."
  cd "${VM_BACKUP_DIR}"
  ${ARCHIVE_CMD} "${VM_NAME}.${ARCHIVE_EXT}" *
  echo ">>>>>>>>>> Removing files that have been archived..."
  find "${VM_BACKUP_DIR}" ! -name *.${ARCHIVE_EXT} -type f -print0 | xargs -0 rm
}

#----------------------------------------------------------
# Function: terminate
# Purpose : Terminate the script
#----------------------------------------------------------
terminate() {
  # Clean up temporary VM List 
  if [ ${DEBUG_MODE} -eq 0 ]; then
    rm -f ${VM_LIST}
  fi
  if [ $1 -eq 1 ]; then
    echo -e "Error: Script did not complete."
    echo "###########################################################"
    exit 1
  else
    echo "###########################################################"
    exit 0
  fi
}

#----------------------------------------------------------
# Function: sanityCheck <ARGCOUNT>
# Purpose : Check runtime environment, parameters,
#           available commands, etc. to ensure that script
#           is going to run ok.
#----------------------------------------------------------
sanityCheck() {
	NUM_OF_ARGS=$1

	if [ ! ${NUM_OF_ARGS} == 1 ]; then
		printUsage
		terminate 0
	fi

  VMWARE_CMD=`which vmware-vim-cmd`
  if [ ! -x $VMWARE_CMD ]; then
    if [ -f /usr/bin/vmware-vim-cmd ]; then
      VMWARE_CMD=/usr/bin/vmware-vim-cmd
	  else
	    echo "Cannot locate vmware-vim-cmd. Are you running VMware Server?"
	    terminate 1
	  fi
	fi
  if [ ! -z $VM_USER ]; then
    debugVar "VM_USER Detected" "$VM_USER"
    VMWARE_CMD="$VMWARE_CMD -U $VM_USER"
  fi
  if [ ! -z $VM_PASSWORD ]; then
    debugVar "VM_PASSWORD Detected" "$VM_PASSWORD"
    VMWARE_CMD="$VMWARE_CMD -P $VM_PASSWORD"
  fi

  RSYNC_FLAG=0
  if [ -x `which rsync` ]; then
    RSYNC_FLAG=1
  fi

  if [ -x `which bzip2` ]; then
    ARCHIVE_CMD="tar cjvf"
    ARCHIVE_EXT="tar.bz"
  elif [ -x `which gzip` ]; then
    ARCHIVE_CMD="tar czvf"
    ARCHIVE_EXT="tgz"
  else
    ARCHIVE_CMD="tar cvf"
    ARCHIVE_EXT="tar"
  fi

	if [ ! -f ${FILE_INPUT} ]; then
		echo -e "Error: ${FILE_INPUT} is not a valid VM input file!\n"
		printUsage
	fi

  if [ ! -d ${VM_BACKUP_VOLUME} ]; then
    echo -e "Error: Backup location \"${VM_BACKUP_VOLUME}\" does not exist!\n"
    terminate 1
  elif [ ! -w ${VM_BACKUP_VOLUME} ]; then
    echo -e "Error: Backup location \"${VM_BACKUP_VOLUME}\" is not writable!\n"
    terminate 1
  fi

}

#----------------------------------------------------------
# Function: serverVCB
# Purpose : This is the main program
#----------------------------------------------------------
serverVCB() {

	VM_INPUT=$1

  START_TIME=`date`
  S_TIME=`date +%s`

  VM_LIST=`mktemp` || exit 1
	#dump out all virtual machines allowing for spaces
	${VMWARE_CMD} vmsvc/getallvms | grep ^[0-9] | sed 's/[[:blank:]]\{3,\}/   /g' | awk -F'   ' '{print "\""$1"\";\""$2"\";\""$3"\""}' |  sed 's/\] /\]\";\"/g' > $VM_LIST
	
	# Get the VMware Product Line
  getProduct
	debugVar "VMware Product Line" $productLineId

  OLD_IFS=$IFS
	IFS=$'\n'
	VM_COUNT=`cat "${VM_INPUT}" | sed '/^[[:blank:]]*$/d' | wc -l`
	VM_COUNT_SUCCESS=0
	VM_COUNT_FAIL=0
	VM_ITER=0
	for VM_NAME in `cat "${VM_INPUT}" | sed '/^[[:blank:]]*$/d'`;
    do
    VM_ITER=$[ ${VM_ITER}+1 ]
		VM_ID=`grep -E "\"${VM_NAME}\"" ${VM_LIST} | awk -F ";" '{print $1}' | sed 's/"//g'`

		#ensure default value if one is not selected or variable is null
		if [ -z ${VM_BACKUP_DIR_NAMING_CONVENTION} ]; then
			VM_BACKUP_DIR_NAMING_CONVENTION="$(date +%F)"
		fi

		VMFS_VOLUME=`grep -E "\"${VM_NAME}\"" ${VM_LIST} | awk -F ";" '{print $3}' | sed -e 's/\[//;s/\]//;s/"//g' -e 's/ /\\\ /g'`
		VMX_CONF=`grep -E "\"${VM_NAME}\"" ${VM_LIST} | awk -F ";" '{print $4}' | sed 's/\[//;s/\]//;s/"//g'`
		if [ -z "${VMFS_VOLUME}" ]; then
		  VMX_PATH="${VMX_CONF}"
		else
		  getVimVar "hostsvc/datastore/info \"${VMFS_VOLUME}\"" path VMFS_PATH
		  VMX_PATH="${VMFS_PATH}/${VMX_CONF}"
		fi
	
		VMX_DIR=`dirname "${VMX_PATH}"`

		debugVar "Virtual Machine" $VM_NAME
		debugVar VM_ID $VM_ID
		debugVar VMX_PATH $VMX_PATH
		debugVar VMX_DIR $VMX_DIR
		debugVar VMX_CONF $VMX_CONF
		debugVar VMFS_VOLUME $VMFS_VOLUME
		debugVar VM_BACKUP_DIR_NAMING_CONVENTION $VM_BACKUP_DIR_NAMING_CONVENTION

		IFS=$OLD_IFS

		#checks to see if we can pull out the VM_ID
		if [ -z ${VM_ID} ]; then
			echo "Error: Failed to extract VM_ID for VM identified as \"${VM_NAME}\"!"
			echo ">!>!>!>!>! The following Virtual Machines are known:"
			awk -F ";" '{print $2}' ${VM_LIST} | sed 's/"//g' | sort
			echo "<!<!<!<!<! Ensure that name and case match!"
      VM_COUNT_FAIL=$[ ${VM_COUNT_FAIL}+1 ]

    #checks to see if the VM has any snapshots to start with
    elif ls "${VMX_DIR}" | grep -q -E "[0-9]{6}" > /dev/null 2>&1; then
	    echo "Warning: Snapshot found for ${VM_NAME}, backup will not take place"
      VM_COUNT_FAIL=$[ ${VM_COUNT_FAIL}+1 ]
      continue
      
		#checks to see if the VM has an RDM <- Not sure if Server can do this any more - better safe than sorry
		elif ${VMWARE_CMD} vmsvc/device.getdevices ${VM_ID} | grep "RawDiskMapping" > /dev/null 2>&1; then
			echo "Warning: RDM was found for ${VM_NAME}, backup will not take place"
      VM_COUNT_FAIL=$[ ${VM_COUNT_FAIL}+1 ]
      continue

    elif [[ -f "${VMX_PATH}" ]] && [[ ! -z "${VMX_PATH}" ]]; then

	    BACKUP_DIR=`echo "${VM_BACKUP_VOLUME}/${VM_NAME}"`
	    BACKUP_DIR_ESCAPED=`echo "${VM_BACKUP_VOLUME}/${VM_NAME}" | sed 's/ /\\\ /g'`
      if [[ -z ${VM_BACKUP_VOLUME} ]]; then
        echo "Error: Variable VM_BACKUP_VOLUME was not defined"
        terminate 1
      fi

			#initial root VM backup directory
			if [ ! -d "${BACKUP_DIR}" ]; then
				mkdir -p "${BACKUP_DIR}"
	    fi

			# directory name of the individual Virtual Machine backup followed by naming convention followed by count
			VM_NAME_DIR=`echo ${VM_NAME} | sed 's/ /\\\ /g'`
			VM_BACKUP_DIR="${BACKUP_DIR}/${VM_NAME}-${VM_BACKUP_DIR_NAMING_CONVENTION}"
			VM_BACKUP_DIR_ESCAPED="${BACKUP_DIR_ESCAPED}/${VM_NAME_DIR}-${VM_BACKUP_DIR_NAMING_CONVENTION}"
			
			debugVar VM_BACKUP_VOLUME "$VM_BACKUP_VOLUME"
			debugVar BACKUP_DIR "$BACKUP_DIR"
			debugVar BACKUP_DIR_ESCAPED "$BACKUP_DIR_ESCAPED"
			debugVar VM_BACKUP_DIR "$VM_BACKUP_DIR"
			debugVar VM_BACKUP_DIR_ESCAPED "$VM_BACKUP_DIR_ESCAPED"

      echo "++++++++++ Backup ${VM_ITER} of ${VM_COUNT}"
      echo "++++++++++ Initiating backup process for ${VM_NAME}"
			mkdir -p "${VM_BACKUP_DIR}"

			cp -p "${VMX_PATH}" "${VM_BACKUP_DIR}"

			ORGINAL_VM_POWER_STATE=$(${VMWARE_CMD} vmsvc/power.getstate ${VM_ID} | tail -1)

		  debugVar ORGINAL_VM_POWER_STATE "$ORGINAL_VM_POWER_STATE"
		  debugVar POWER_VM_DOWN_BEFORE_BACKUP "$POWER_VM_DOWN_BEFORE_BACKUP"

			#section that will power down a VM prior to taking a snapshot and backup and power it back on
			if [ ${POWER_VM_DOWN_BEFORE_BACKUP} -eq 1 ]; then
				START_ITERATION=0
				echo "Powering off initiated for ${VM_NAME}, backup will not begin until VM is off..."
				${VMWARE_CMD} vmsvc/power.shutdown ${VM_ID} > /dev/null 2>&1
				while ${VMWARE_CMD} vmsvc/power.getstate ${VM_ID} | grep -i "Powered on" > /dev/null 2>&1;
				do
					START_ITERATION=$((START_ITERATION + 1))
					#enable hard power off code
					if [ ${ENABLE_HARD_POWER_OFF} -eq 1 ]; then
						if [ ${START_ITERATION} -gt ${ITER_TO_WAIT_SHUTDOWN} ]; then
							echo "Hard power off occured for ${VM_NAME}, waited for $((ITER_TO_WAIT_SHUTDOWN*3)) seconds" 
							${VMWARE_CMD} vmsvc/power.off ${VM_ID} > /dev/null 2>&1 
							#this is needed for ESXi, even the hard power off did not take affect right away
							sleep 5
							break
						fi
					fi
          echo "---------- VM ${VM_NAME} is still on - Iteration: ${START_ITERATION} - waiting 3secs"
          sleep 3
				done 
				echo ">>>>>>>>>> VM ${VM_NAME} is off"
			fi

			#powered on VMs only
			if [[ ! ${POWER_VM_DOWN_BEFORE_BACKUP} -eq 1 ]] && [[ "${ORGINAL_VM_POWER_STATE}" != "Powered off" ]]; then
				echo ">>>>>>>>>> Taking backup snapshot for ${VM_NAME} ..."
				${VMWARE_CMD} vmsvc/snapshot.create ${VM_ID} vcb_snap VCB_BACKUP_${VM_NAME}_`date +%F` > /dev/null 2>&1
				echo ">>>>>>>>>> Done: Snapshot creation"
			fi

      if [ "${productLineId}" == "gsx" ]; then
        gsxVmdkBackup
        if [ ${ENABLE_ARCHIVING} -eq 1 ]; then
          archiveBackup
        fi
      else
        esxVmdkBackup
        terminate 0
      fi

			#powered on VMs only w/snapshots
			if [[ ! ${POWER_VM_DOWN_BEFORE_BACKUP} -eq 1 ]] && [[ "${ORGINAL_VM_POWER_STATE}" == "Powered on" ]]; then
        echo ">>>>>>>>>> Removing snapshot from ${VM_NAME} ..."
				${VMWARE_CMD} vmsvc/snapshot.remove ${VM_ID} > /dev/null 2>&1

        getSnapshotTasks

        for TASK in ${SNAPSHOT_TASKS};
        do
          getSnapshotStatus "${TASK}"
        done
        echo ">>>>>>>>>> ${state}: Snapshot removal"
      
				#do not continue until all snapshots have been committed
        echo ">>>>>>>>>> Waiting for snapshot on ${VM_NAME} to be committed..."
		    while ls "${VMX_DIR}" | grep -q -E "[0-9]{6}";
        do
          sleep 3
        done
        echo ">>>>>>>>>> Done: Snapshot committed"
			fi

			if [[ ${POWER_VM_DOWN_BEFORE_BACKUP} -eq 1 ]] && [[ "${ORGINAL_VM_POWER_STATE}" == "Powered on" ]]; then
				#power on vm that was powered off prior to backup
				echo ">>>>>>>>>> Powering back on ${VM_NAME}"
				${VMWARE_CMD} vmsvc/power.on ${VM_ID} > /dev/null 2>&1
			fi	

			checkVMBackupRotation "${BACKUP_DIR}" "${VM_BACKUP_DIR}"

			echo -e "^^^^^^^^^^ Completed backup for ${VM_NAME}!\n"
    else
      echo "Error: Failed to lookup ${VM_NAME}!"
      VM_COUNT_FAIL=$[ ${VM_COUNT_FAIL}+1 ]
    fi
  done
	unset IFS

	echo
  echo "##################### Summary #############################"
  echo "Virtual Machines to backup: ${VM_COUNT}"
  echo "Successfully backed up    : ${VM_COUNT_SUCCESS}"
  echo "Failed to back up         : ${VM_COUNT_FAIL}"
  echo "###########################################################"
  END_TIME=`date`
  E_TIME=`date +%s`
  echo "Start time: ${START_TIME}"
  echo "End   time: ${END_TIME}"
  DURATION=`echo $((E_TIME - S_TIME))`

  #calculate overall completion time
  if [ ${DURATION} -le 60 ]; then
          echo -e "Duration  : ${DURATION} Seconds\n"
  else
          echo -e "Duration  : `awk 'BEGIN{ printf "%.2f\n", '${DURATION}'/60}'` Minutes\n"
  fi

	terminate 0
}

#----------------------------------------------------------
# Start of Script
#----------------------------------------------------------
echo "###########################################################"
echo "# VMware Server Backup Script Version: $VERSION"
echo "###########################################################"

# Do a sanity check
sanityCheck $#

# Run the main program
serverVCB $1
