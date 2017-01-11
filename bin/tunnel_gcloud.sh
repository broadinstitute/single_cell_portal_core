#!/usr/bin/env bash

# usage error message
usage=$(
cat <<EOF
$0 [OPTION]
-e VALUE	set the environment, defaults to 'production' (determines which VM to ssh into).
-H COMMAND	print this text
EOF
)

# set variables & defaults
ENV="production"
while getopts "e:H" OPTION; do
case $OPTION in
	e)
		ENV="$OPTARG"
		;;
	H)
		echo "$usage"
		exit 0
		;;
	*)
    echo "unrecognized option"
    echo "$usage"
    ;;
	esac
done

gcloud compute ssh singlecell-$ENV --project broad-singlecellportal --zone us-central1-a