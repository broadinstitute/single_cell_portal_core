# use KDUX base Rails image, configure only project-specific items here
FROM broadinstitute/kdux-rails-baseimage

# Set up project dir, install gems, set up script to migrate database and precompile static assets on run
RUN mkdir /home/app/webapp
COPY Gemfile /home/app/webapp/Gemfile
COPY Gemfile.lock /home/app/webapp/Gemfile.lock
WORKDIR /home/app/webapp
RUN bundle install
# COPY set_user_permissions.bash /etc/my_init.d/01_set_user_permissions.bash
COPY rails_startup.bash /etc/my_init.d/02_rails_startup.bash

# Configure NGINX
RUN rm /etc/nginx/sites-enabled/default
COPY webapp.conf /etc/nginx/sites-enabled/webapp.conf
COPY nginx.conf /etc/nginx/nginx.conf
RUN rm -f /etc/service/nginx/down

# Compile native support for passenger for Ruby 2.2
RUN sudo -E -u app passenger-config build-native-support