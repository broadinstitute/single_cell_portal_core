#! /usr/bin/env bash

# script to add to root crontab on a deployed host to check for crashed Docker containers and restart
# crontab entry should be as follows:
# */5 * * * * /root/restart_portal_container.sh > /dev/null 2>&1
docker ps --filter "status=exited" | grep -e 'single_cell' | while read -r line ; do
	container_id=`echo $line | awk '{print $1}'`
	container_name=`echo $line | awk '{print $NF}'`
	echo "Restarting $container_name ($container_id) on $(date)" >> /home/jenkins/deployments/single_cell_portal_core/log/cron_out.log
	docker restart $container_id
done
