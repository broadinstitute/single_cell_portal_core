#!/bin/bash

cd /home/app/webapp
echo "*** CLEARING TMP CACHE ***"
sudo -E -u app -H bin/rails RAILS_ENV=$PASSENGER_APP_ENV tmp:clear
echo "*** COMPLETED ***"
echo "*** ROLLING OVER LOGS ***"
ruby /home/app/webapp/bin/cycle_logs.rb
echo "*** COMPLETED ***"

# ensure data upload directory exists and has correct permissions
echo "*** ENSURING DATA UPLOAD DIRECTORY PERMISSIONS ***"
if [[ ! -d /home/app/webapp/data ]]; then
    echo "DATA DIRECTORY NOT PRESENT; CREATING"
    mkdir data
    echo "DATA DIRECTORY SUCCESSFULLY CREATED"
fi
sudo chown -R app:app /home/app/webapp/data
echo "*** COMPLETED ***"

if [[ $PASSENGER_APP_ENV = "production" ]] || [[ $PASSENGER_APP_ENV = "staging" ]] || [[ $PASSENGER_APP_ENV = "pentest" ]]
then
    echo "*** PRECOMPILING ASSETS ***"
    # see https://github.com/rails/webpacker/issues/1189#issuecomment-359360326
    export NODE_OPTIONS="--max-old-space-size=4096"
    sudo -E -u app -H bundle exec rake NODE_ENV=production RAILS_ENV=$PASSENGER_APP_ENV SECRET_KEY_BASE=$SECRET_KEY_BASE assets:clean
    sudo -E -u app -H NODE_ENV=production RAILS_ENV=$PASSENGER_APP_ENV yarn install
    if [ $? -ne 0 ]; then
        # since node-sass has OS-dependent bindings, calling upgrade will force those bindings to install and prevent
        # the call to rake assets:precompile from failing due to the 'vendor' directory not being there
        sudo -E -u app -H NODE_ENV=production RAILS_ENV=$PASSENGER_APP_ENV yarn upgrade node-sass
        sudo -E -u app -H NODE_ENV=production RAILS_ENV=$PASSENGER_APP_ENV yarn install --force
    fi
    sudo -E -u app -H bundle exec rake NODE_ENV=production RAILS_ENV=$PASSENGER_APP_ENV SECRET_KEY_BASE=$SECRET_KEY_BASE assets:precompile
    echo "*** COMPLETED ***"
elif [[ $PASSENGER_APP_ENV = "development" ]]; then
    echo "*** UPGRADING/COMPILING NODE MODULES ***"
    # force upgrade in local development to ensure yarn.lock is continually updated
    sudo -E -u app -H mkdir -p /home/app/.cache/yarn
    sudo -E -u app -H yarn install
    if [ $? -ne 0 ]; then
       sudo -E -u app -H yarn install --force
    fi
    sudo -E -u app -H /home/app/webapp/bin/webpack
fi
if [[ -n $TCELL_AGENT_APP_ID ]] && [[ -n $TCELL_AGENT_API_KEY ]] ; then
    echo "*** CONFIGURING TCELL WAF ***"
    sudo -E -u app -Hs /home/app/webapp/bin/configure_tcell.rb
    echo "*** COMPLETED ***"
fi
echo "*** CREATING CRON ENV FILES ***"
echo "export PROD_DATABASE_PASSWORD='$PROD_DATABASE_PASSWORD'" >| /home/app/.cron_env
echo "export SENDGRID_USERNAME='$SENDGRID_USERNAME'" >> /home/app/.cron_env
echo "export SENDGRID_PASSWORD='$SENDGRID_PASSWORD'" >> /home/app/.cron_env
echo "export MONGO_LOCALHOST='$MONGO_LOCALHOST'" >> /home/app/.cron_env
echo "export MONGO_INTERNAL_IP='$MONGO_INTERNAL_IP'" >> /home/app/.cron_env
echo "export SECRET_KEY_BASE='$SECRET_KEY_BASE'" >> /home/app/.cron_env
echo "export GOOGLE_CLOUD_PROJECT='$GOOGLE_CLOUD_PROJECT'" >> /home/app/.cron_env

if [[ -z $SERVICE_ACCOUNT_KEY ]]; then
	echo $GOOGLE_CLOUD_KEYFILE_JSON >| /home/app/.google_service_account.json
	chmod 400 /home/app/.google_service_account.json
	chown app:app /home/app/.google_service_account.json
	echo "export SERVICE_ACCOUNT_KEY='/home/app/.google_service_account.json'" >> /home/app/.cron_env
else
	echo "export SERVICE_ACCOUNT_KEY='$SERVICE_ACCOUNT_KEY'" >> /home/app/.cron_env
fi

if [[ -n "$READ_ONLY_SERVICE_ACCOUNT_KEY" ]]; then
	echo "export READ_ONLY_SERVICE_ACCOUNT_KEY='$READ_ONLY_SERVICE_ACCOUNT_KEY'" >> /home/app/.cron_env
else
	echo "*** NO READONLY SERVICE ACCOUNT DETECTED -- SOME FUNCTIONALITY WILL BE DISABLED ***"
fi

chmod 400 /home/app/.cron_env
chown app:app /home/app/.cron_env
echo "*** COMPLETED ***"

echo "*** RUNNING PENDING MIGRATIONS ***"
sudo -E -u app -H bin/rake RAILS_ENV=$PASSENGER_APP_ENV db:migrate
echo "*** COMPLETED ***"

if [[ ! -d /home/app/webapp/tmp/pids ]]
then
    echo "*** MAKING tmp/pids DIR ***"
    sudo -E -u app -H mkdir -p /home/app/webapp/tmp/pids || { echo "FAILED to create ./tmp/pids/" >&2; exit 1; }
    echo "*** COMPLETED ***"
fi
echo "*** STARTING DELAYED_JOB for $PASSENGER_APP_ENV env ***"
rm tmp/pids/delayed_job.*.pid
sudo -E -u app -H bin/delayed_job start $PASSENGER_APP_ENV --pool=default:6, --pool=cache:2 || { echo "FAILED to start DELAYED_JOB " >&2; exit 1; }
echo "*** ADDING CRONTAB TO CHECK DELAYED_JOB ***"
echo "*/15 * * * * . /home/app/.cron_env ; /home/app/webapp/bin/job_monitor.rb -e=$PASSENGER_APP_ENV >> /home/app/webapp/log/cron_out.log 2>&1" | crontab -u app -
echo "*** COMPLETED ***"

echo "*** REINDEXING DATABASE ***"
sudo -E -u app -H bin/bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV db:mongoid:create_indexes
echo "*** COMPLETED ***"

echo "*** ADDING CRONTAB TO REINDEX DATABASE ***"
(crontab -u app -l ; echo "@daily . /home/app/.cron_env ; cd /home/app/webapp/; bin/bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV db:mongoid:create_indexes >> /home/app/webapp/log/cron_out.log 2>&1") | crontab -u app -
echo "*** COMPLETED ***"

if [[ $PASSENGER_APP_ENV = "development" ]]
then
  echo "*** DELETING QUEUED STUDIES & FILES ***"
  # run cleanups at boot, don't run crons to reduce memory usage
	sudo -E -u app -H bin/rails runner -e $PASSENGER_APP_ENV "StudyFile.delay.delete_queued_files"
	sudo -E -u app -H bin/rails runner -e $PASSENGER_APP_ENV "UserAnnotation.delay.delete_queued_annotations"
	sudo -E -u app -H bin/rails runner -e $PASSENGER_APP_ENV "Study.delay.delete_queued_studies"
else
  echo "*** ADDING CRONTAB TO DELETE FAILED UPLOADS, QUEUED STUDIES & FILES ***"
  # check for failed uploads every 6 hours, run delete queues nightly
	(crontab -u app -l ; echo "0 */6 * * * . /home/app/.cron_env ; cd /home/app/webapp/; /home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV \"UploadCleanupJob.find_and_remove_failed_uploads\" >> /home/app/webapp/log/cron_out.log 2>&1") | crontab -u app -
	(crontab -u app -l ; echo "0 1 * * * . /home/app/.cron_env ; cd /home/app/webapp/; /home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV \"Study.delete_queued_studies\" >> /home/app/webapp/log/cron_out.log 2>&1") | crontab -u app -
	(crontab -u app -l ; echo "0 1 * * * . /home/app/.cron_env ; cd /home/app/webapp/; /home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV \"StudyFile.delete_queued_files\" >> /home/app/webapp/log/cron_out.log 2>&1") | crontab -u app -
	(crontab -u app -l ; echo "0 1 * * * . /home/app/.cron_env ; cd /home/app/webapp/; /home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV \"UserAnnotation.delete_queued_annotations\" >> /home/app/webapp/log/cron_out.log 2>&1") | crontab -u app -
	# clean up cached failed ingest runs weekly
  (crontab -u app -l ; echo "@weekly . /home/app/.cron_env ; cd /home/app/webapp/; /home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV \"FileParseService.clean_up_ingest_artifacts\" >> /home/app/webapp/log/cron_out.log 2>&1") | crontab -u app -
fi
echo "*** COMPLETED ***"

if [[ $PASSENGER_APP_ENV = "production" ]]
then
  echo "*** ADDING NIGHTLY ADMIN EMAIL ***"
  (crontab -u app -l ; echo "55 23 * * * . /home/app/.cron_env ; cd /home/app/webapp/; /home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV \"SingleCellMailer.nightly_admin_report.deliver_now\" >> /home/app/webapp/log/cron_out.log 2>&1") | crontab -u app -
  echo "*** COMPLETED ***"
fi

if [[ $PASSENGER_APP_ENV != "production" ]]
then
  echo "*** RESETTING DEFAULT INGEST DOCKER IMAGE ***"
  sudo -E -u app -H bin/rails runner -e $PASSENGER_APP_ENV "AdminConfiguration.revert_ingest_docker_image"
  echo "*** COMPLETED ***"
fi


echo "*** ADDING DAILY RESET OF USER DOWNLOAD QUOTAS ***"
(crontab -u app -l ; echo "@daily . /home/app/.cron_env ; cd /home/app/webapp/; /home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV \"User.update_all(daily_download_quota: 0)\" >> /home/app/webapp/log/cron_out.log 2>&1") | crontab -u app -
echo "*** COMPLETED ***"

echo "*** LOCALIZING USER ASSETS ***"
/home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV "UserAssetService.delay.localize_assets_from_remote"
echo "*** COMPLETED ***"

echo "*** CLEARING CACHED USER OAUTH TOKENS ***"
/home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV "User.update_all(refresh_token: nil, access_token: nil, api_access_token: nil)"
echo "*** COMPLETED ***"

echo "*** ADDING REPORTING CRONS ***"
(crontab -u app -l ; echo "5 0 * * Sun . /home/app/.cron_env ; cd /home/app/webapp/; /home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV \"ReportTimePoint.weekly_returning_users\" >> /home/app/webapp/log/cron_out.log 2>&1") | crontab -u app -
(crontab -u app -l ; echo "@daily . /home/app/.cron_env ; cd /home/app/webapp/; /home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV \"AnalysisSubmission.update_running_submissions\" >> /home/app/webapp/log/cron_out.log 2>&1") | crontab -u app -
echo "*** COMPLETED ***"

echo "*** SENDING RESTART NOTIFICATION ***"
sudo -E -u app -H /home/app/webapp/bin/rails runner -e $PASSENGER_APP_ENV "AdminConfiguration.restart_notification"
