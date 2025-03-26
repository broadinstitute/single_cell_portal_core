#! /bin/sh

bundle install
bin/rails db:migrate
bin/delayed_job start development --pool=default:6, --pool=cache:2
RUBYOPT=--disable-frozen-string-literal bin/rails s
