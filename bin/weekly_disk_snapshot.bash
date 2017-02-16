#!/usr/bin/env bash
# create a date stamp for filename
TODAY="$(date +%Y-%m-%d)"

# create the snapshots for portal and data disk
echo "gcloud compute disks snapshot singlecell-production-disk --snapshot-names portal-backup-${TODAY} --zone us-central1-a"
echo "gcloud compute disks snapshot singlecell-production-data --snapshot-names data-backup-${TODAY} --zone us-central1-a"

#
# DELETE OLD SNAPSHOTS (OLDER THAN 1 MONTH)
#
# get a list of existing snapshots
SNAPSHOT_LIST="$(gcloud compute snapshots list | awk '{print $1}' | sed '/NAME/ d')"

# loop through the snapshots
echo "${SNAPSHOT_LIST}" | while read line ; do

	# get the snapshot name
	SNAPSHOT_NAME="${line##*/}"

	# get the date that the snapshot was created
	SNAPSHOT_DATETIME="$(gcloud compute snapshots describe ${SNAPSHOT_NAME} | grep 'creationTimestamp' | cut -d " " -f 2 | tr -d \')"

	# format the date
	SNAPSHOT_DATETIME="$(date -d ${SNAPSHOT_DATETIME} +%Y%m%d)"

	# get the expiry date for snapshot deletion (currently 1 month)
	SNAPSHOT_EXPIRY="$(date -d "-1 month" +"%Y%m%d")"

   	# check if the snapshot is older than expiry date
	if [ $SNAPSHOT_EXPIRY -ge $SNAPSHOT_DATETIME ];
	then
	 # delete the snapshot
		# echo "$(gcloud compute snapshots delete ${SNAPSHOT_NAME} --quiet)"
		echo "$SNAPSHOT_NAME would be deleted - created at $SNAPSHOT_DATETIME"
	fi
done