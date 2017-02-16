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

echo "*** CREATING CRON ENV FILES ***"
echo "export PROD_DATABASE_PASSWORD=$PROD_DATABASE_PASSWORD" >> /root/.cron_env
echo "export SENDGRID_USERNAME=$SENDGRID_USERNAME" >> /root/.cron_env
echo "export SENDGRID_PASSWORD=$SENDGRID_PASSWORD" >> /root/.cron_env
chmod 400 /root/.cron_env
cp /root/.cron_env /home/app/.cron_env
chown app:app /home/app/.cron_env
echo "*** DONE ***"

if [[ -e /home/app/webapp/bin/delayed_job ]]
then
    echo "*** STARTING DELAYED_JOB ***"
    sudo -E -u app -H bin/delayed_job start $PASSENGER_APP_ENV -n 4
    echo "*** ADDING CRONTAB TO CHECK DELAYED_JOB ***"
    echo "* * * * */15 . /home/app/.cron_env ; /home/app/webapp/bin/job_monitor.rb $PASSENGER_APP_ENV" | crontab -u app -
    echo "*** COMPLETED ***"
fi
echo "*** ADDING DAILY ADMIN DISK MONITOR EMAIL ***"
echo "* 3 * * * . /root/.cron_env ; /home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV \"SingleCellMailer.daily_disk_status.deliver\"" | crontab -u root -
echo "*** COMPLETED ***"
echo "*** REINDEXING COLLECTIONS ***"
sudo -E -u app -H bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV db:mongoid:create_indexes
echo "*** COMPLETED ***"