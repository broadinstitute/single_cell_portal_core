# use SCP base Rails image, configure only project-specific items here
FROM gcr.io/broad-singlecellportal-staging/rails-baseimage:2.2.0

# Set ruby version
RUN bash -lc 'rvm --default use ruby-3.1.3'
RUN bash -lc 'rvm rvmrc warning ignore /home/app/webapp/Gemfile'

# Set up project dir, install gems, set up script to migrate database and precompile static assets on run
RUN mkdir /home/app/webapp
RUN sudo chown app:app /home/app/webapp # fix permission issues in local development on MacOSX
RUN gem update --system
RUN gem install bundler
COPY Gemfile /home/app/webapp/Gemfile
COPY Gemfile.lock /home/app/webapp/Gemfile.lock
WORKDIR /home/app/webapp
RUN bundle install

# install JS dependencies
COPY package.json /home/app/webapp/package.json
COPY yarn.lock /home/app/webapp/yarn.lock
RUN chmod a+w /home/app/webapp/yarn.lock
RUN yarn install --force

# copy startup scripts
COPY set_user_permissions.bash /etc/my_init.d/01_set_user_permissions.bash
COPY generate_dh_parameters.bash /etc/my_init.d/02_generate_dh_parameters.bash
COPY rails_startup.bash /etc/my_init.d/03_rails_startup.bash

# Configure NGINX
RUN rm /etc/nginx/sites-enabled/default
COPY webapp.conf /etc/nginx/sites-enabled/webapp.conf
COPY nginx.conf /etc/nginx/nginx.conf
RUN rm -f /etc/service/nginx/down

# Compile native support for passenger for Ruby
RUN passenger-config build-native-support
