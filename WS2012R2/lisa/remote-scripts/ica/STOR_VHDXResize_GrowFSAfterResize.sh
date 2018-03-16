#!/bin/bash

########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved. 
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0  
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################
# STOR_VHDXResize_GrowFSAfterResize.sh
# Description:
#     This script will verify if you can resize the filesystem on a resized  
#     VHDx file
#     Hyper-V setting pane. The test performs the following
#     step
#    1. Restores partition
#    2. Checks the filesystem
#    3. Perform filesystem resize
#    4. Mounts the partition
#    5. Performs read/write operations
#    6. Unmounts partition
#    7. Deletes partition  
#
########################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

cd ~

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

# Source the constants file
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#Prepare Read/Write script for execution
dos2unix STOR_VHDXResize_ReadWrite.sh
chmod +x STOR_VHDXResize_ReadWrite.sh
#
# Verify if guest sees the drive
#
if [ ! -e "/dev/sdb" ]; then
    msg="The Linux guest cannot detect the drive"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
LogMsg "The Linux guest detected the drive"

count=0
for fs in "${fileSystems[@]}"; do

    #
    # Restore the partition
    #
    (echo n; echo p; echo 1; echo ; echo ;echo w) | fdisk /dev/sdb 2> /dev/null
    if [ $? -gt 0 ]; then
        LogMsg "Failed to restore partition"
        echo "Restore partition: Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi
    LogMsg "Partition restored"

    sleep 5

    # Format the partition
    LogMsg "Info: Start testing filesystem: $fs"
    command -v mkfs.$fs
    if [ $? -ne 0 ]; then
        echo "Error: File-system tools for $fs not present. Skipping filesystem $fs.">> ~/summary.log
        LogMsg "Error: File-system tools for $fs not present. Skipping filesystem $fs."
        count=`expr $count + 1`
        continue
    else
        #Use -f option for xfs filesystem, but ignore parameter for other filesystems
        option=""
        if [ "$fs" = "xfs" ]; then
            option="-f"
        fi
        mkfs -t $fs $option /dev/sdb1 2> ~/summary.log
        if [ $? -ne 0 ]; then
            LogMsg "Error: Failed to format partition with $fs"
            echo "Error: Formating partition: Failed with $fs" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 10
        fi
        LogMsg "Info: Successfully formated partition with $fs"
    fi

    #
    # Checking filesystem
    # Because e2fsck and resize2fs only work for ext filesystems
    # we need to skip xfs for now
    if [ ! "$fs" = "xfs" ]; then
        e2fsck -y -v -f /dev/sdb1
        if [ $? -gt 0 ]; then
            LogMsg "Failed to check filesystem"
            echo "Checking filesystem: Failed" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 10
        fi
        LogMsg "Filesystem checked"
    fi

    #
    # Resizing the filesystem 
    #
    if [ ! "$fs" = "xfs" ]; then
        resize2fs /dev/sdb1
        if [ $? -gt 0 ]; then
            LogMsg "Failed to resize filesystem"
            echo "Resizing the filesystem: Failed" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 10
        fi
    fi    
    LogMsg "Filesystem resized"

    #
    # Mount partition
    #
    if [ ! -e "/mnt" ]; then
        mkdir /mnt 2> ~/summary.log
        if [ $? -gt 0 ]; then
            LogMsg "Failed to create mount point"
            echo "Creating mount point: Failed" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 10
        fi
        LogMsg "Mount point /dev/mnt created"
    fi

    mount /dev/sdb1 /mnt 2> ~/summary.log
    if [ $? -gt 0 ]; then
        LogMsg "Failed to mount partition"
        echo "Mounting partition: Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi
    LogMsg "Partition mount successful"
    
    # If the partition was successfully mounted we can use xfs_growsfs to
    # check the XFS filesystem also
    if [ "$fs" = "xfs" ]; then
        xfs_growfs -d /dev/sdb1
        if [ $? -gt 0 ]; then
            LogMsg "Failed to resize filesystem"
            echo "Resizing the filesystem: Failed" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 10
        fi
    fi

    #
    # Read/Write mount point
    #
    ./STOR_VHDXResize_ReadWrite.sh

    #
    # Restore ICA folder
    #
    mkdir /mnt/ICA/ 2> ~/summary.log
    if [ $? -gt 0 ]; then
        LogMsg "Failed to restore directory /mnt/ICA/"
        echo "Restoring /mnt/ICA/ directory: Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi

    umount /mnt
    if [ $? -gt 0 ]; then
        LogMsg "Failed to unmount partition"
        echo "Unmounting partition: Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi

    (echo d; echo w) | fdisk /dev/sdb 2> ~/summary.log
    if [ $? -gt 0 ]; then
        LogMsg "Failed to delete partition"
        echo "Deleting partition: Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi
    LogMsg "Delete partition successful"

done
UpdateTestState $ICA_TESTCOMPLETED

exit 0;
