# Developing on SCP without a Docker container

Developing on SCP without a Docker container, while less robust, opens up some faster development paradigms, including live css/js reloading, faster build times, and byebug debugging in rails.

## SETUP

1.  Run `ruby -v` to ensure Ruby 2.5.7 is installed on your local machine.  If not, [install rvm](https://rvm.io/rvm/install), then `rvm install 2.5.7`, then `rvm use 2.5.7`.
2.  Run `bundler -v` to ensure Bundler is installed.  If not, `gem install bundler`.
3.  `cd` to where you have the `single_cell_portal_core` Git repo checked out.
4.  Run `bundle install`
5.  Run `yarn install`
6.  Run `ruby rails_local_setup.rb $BROAD_USERNAME`, where $BROAD_USERNAME is a something like eweitz -- this creates a file in config/secrets with commands to export needed environment variables
7.  Run the source command the script outputs -- this will export those needed variables into the current shell
8.  Run `rails s`
9.  (optional, for live reload) In a separate terminal, run bin/webpack-dev-server
10. (needed if you are working on functionality that involves delayed jobs).
    * In another terminal, run the source command output in step 7
    * run `rails jobs:work`
11.  You're all set!  You can now go to localhost:3000 and see the website.

## REGULAR DEVELOPMENT
Adding `source <<path-to-single-cell-portal-core>>/config/secrets/.source_env.bash` to your .bash_profile will source the secrets read from vault to each new shell, saving you the trouble of rerunning the setup process every time you open a new shell.

## KNOWN ISSUES
1. Developing outside the docker container inherently runs more risk that your code will not work in the docker environment in staging/production.  BE CAREFUL.  If your changes are non-trivial, confirm your changes work in the containerized deploy before committing (ESPECIALLY changes involving package.json and/or the Gemfile)
2. You may experience difficulty toggling back and forth between containerized and non-containerized deployment, as node-sass bindings are OS-specific.  If you see an error like 'No matching version of node-sass found'
   * if this error occurs when trying to deploy in the container, fix it by deleting the `node-modules/node-sass` folder, and then rerunning the load_env_secrets process
   * if the error is when you're trying to run locally, fix it by running `npm rebuild node-sass`
