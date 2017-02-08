#!/bin/bash

cd /home/app/webapp
echo "*** CLEARING TMP CACHE ***"
sudo -E -u app -H bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV tmp:clear
echo "*** COMPLETED ***"
if [[ $PASSENGER_APP_ENV = "production" ]] || [[ $PASSENGER_APP_ENV = "staging" ]]
then
    echo "*** PRECOMPILING ASSETS ***"
    sudo -E -u app -H bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV SECRET_KEY_BASE=$SECRET_KEY_BASE assets:clean
    sudo -E -u app -H bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV SECRET_KEY_BASE=$SECRET_KEY_BASE assets:precompile
    echo "*** COMPLETED ***"
fi

if [[ -e /home/app/webapp/bin/delayed_job ]]
then
    echo "*** STARTING DELAYED_JOB ***"
    sudo -E -u app -H bin/delayed_job start $PASSENGER_APP_ENV -n 4
    echo "*** ADDING CRONTAB TO CHECK DELAYED_JOB ***"
    echo "* * * * */15 /home/app/webapp/bin/job_monitor.rb $PASSENGER_APP_ENV" | crontab -u app -
    echo "*** ADDING DAILY ADMIN DISK MONITOR EMAIL ***"
    (crontab -l -u app && echo "* 3 * * * /home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV \"SingleCellMailer.daily_disk_status.deliver\"") | crontab -u app -
    echo "*** COMPLETED ***"
fi
echo "*** REINDEXING COLLECTIONS ***"
sudo -E -u app -H bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV db:mongoid:create_indexes
echo "*** COMPLETED ***"
