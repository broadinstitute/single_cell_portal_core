#! /bin/sh

bundle install
bin/rails db:migrate
bin/delayed_job start development --pool=default:6, --pool=cache:2
bin/rails s
