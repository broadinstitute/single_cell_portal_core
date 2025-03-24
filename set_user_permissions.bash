#!/bin/bash
if [[ $PASSENGER_APP_ENV = "production" ]] || [[ $PASSENGER_APP_ENV = "staging" ]] || [[ $PASSENGER_APP_ENV = "pentest" ]]
then
	set -e # fail on any error

	echo '*** SETTING UID AND GID TO MATCH HOST VOLUMES ***'
	TARGET_UID=$(stat -c "%u" /home/app/webapp)
	echo '-- Setting app user to use uid '$TARGET_UID
	usermod -o -u $TARGET_UID app || true
	TARGET_GID=$(stat -c "%g" /home/app/webapp)
	echo '-- Setting app group to use gid '$TARGET_GID
	groupmod -o -g $TARGET_GID app || true
fi
