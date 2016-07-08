#!/bin/bash

cd /home/app/webapp
echo "*** CLEARING TMP CACHE ***"
sudo -E -u app -H bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV tmp:clear
echo "*** COMPLETED ***"
if [[ $PASSENGER_APP_ENV = "production" ]]
then
    echo "*** PRECOMPILING ASSETS ***"
    rm -rf public/single_cell/assets
    sudo -E -u app -H bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV SECRET_KEY_BASE=$SECRET_KEY_BASE assets:precompile
    echo "*** COMPLETED ***"
fi

if [[ -e /home/app/webapp/bin/delayed_job ]]
then
    echo "*** STARTING DELAYED_JOB ***"
    # sudo -E -u app -H bin/delayed_job start $PASSENGER_APP_ENV -n 4
    echo "*** ADDING CRONTAB TO CHECK DELAYED_JOB ***"
    # echo "* * * * */15 /home/app/webapp/bin/job_monitor.rb $PASSENGER_APP_ENV" | crontab -u app -
    echo "*** COMPLETED ***"
fi
