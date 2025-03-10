#! /usr/bin/env bash

# script to add to the root crontab to remount attached disk in correct location after scheduled instance restart
# crontab should be entered as follows
# @reboot /root/remout_portal_source.sh > /dev/null 2>&1
MOUNT_DIR=$(ls -l /dev/disk/by-id/google-* | grep google-singlecell-data-disk | awk -F '/' '{ print $NF }')
if [[ -n "$MOUNT_DIR" ]]; then
  echo "$(date): remounting google-singlecell-data-disk from /dev/$MOUNT_DIR" >> /home/jenkins/remount_log.txt
  mount -o discard,defaults /dev/$MOUNT_DIR /home/jenkins/deployments
else
  echo -e "$(date): cannot remount google-singlecell-data-disk, available disks:\n$(ls -l /dev/disk/by-id/google-*)" >> /home/jenkins/remount_log.txt
fi
