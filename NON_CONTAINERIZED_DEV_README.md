# Developing on SCP natively, without a Docker container

Developing on SCP natively, i.e. outside a Docker container, is less robust but faster.  In native mode, full pages load are 4-7x faster, tests run faster, and rich [byebug debugging](https://github.com/deivid-rodriguez/byebug/blob/master/GUIDE.md) in Rails is possible.

## SETUP
Commands below assume your CPU is Apple Silicon / M1, not Intel.
1. Append the following to your `~/.zshrc` (if using Z shell macOS default in Terminal, or `~/.bash_profile` if Bash), then run `source ~/.zschrc`:
```
# Avoid compilation errors with occasional Ruby gems, e.g. bson_ext, puma
CFLAGS="-Wno-error=implicit-function-declaration"
```
2. Run `rbenv -v`.  If it is not found, `brew install rbenv`, then `rbenv init` to set up rbenv in your shell, then close terminal and reopen it.
3. Run `ruby -ropenssl -e 'puts OpenSSL::OPENSSL_VERSION'`.  
  - If it outputs contains "OpenSSL 1.1.1", go to Step 4.  
  - Else, if output contains something like "OpenSSL 3.0.7", install the needed version of OpenSSL, and install Ruby so that it compiles with the needed version of OpenSSL:
     - Run `brew install openssl@1.1`
     - Run `rbenv uninstall 3.1.3`
     - Run `LDFLAGS="-L/opt/homebrew/opt/openssl@1.1/lib" CPPFLAGS="-I/opt/homebrew/opt/openssl@1.1/include" CONFIGURE_OPTS="--with-openssl-dir=$(brew --prefix openssl@1.1)" RUBY_CONFIGURE_OPTS="--with-openssl-dir=$(brew --prefix openssl@1.1)" rbenv install 3.1.3`
     - Run `ruby -v` to ensure Ruby 3.1.3 is installed
4. Run `ruby -v` to ensure Ruby 3.1.3 is installed on your local machine.  If not, run `rbenv install 3.1.3` (current [as of 2023-01-26](https://github.com/broadinstitute/single_cell_portal_core/pull/1713)) then `rbenv global 3.1.3`.
5. Run `bundler -v` to ensure Bundler is installed.  If not, `gem install bundler`.
6. Run `node -v` to ensure Node is installed. If not, install via https://nodejs.org/en/download/
7. Run `yarn -v` to ensure Yarn is installed. If not, install via `brew install yarn`
8. `cd` to where you have the `single_cell_portal_core` Git repo checked out.
9. Run `bundle install`
  - That might fail with a message that contains "An error occurred while installing bson_ext"
  - If so, run: ``gem install bson_ext -v '1.5.1' --source 'https://rubygems.org/' -- --with-cflags="-Wno-error=implicit-function-declaration"``
  - If that fails, follow steps from https://stackoverflow.com/a/64248633, i.e.:
    - Run `cd /Users/$(whoami)/.rbenv/versions/3.1.3/lib/ruby/gems/3.1.0/gems/bson_ext-1.5.1/ext/cbson`
    - Insert one line, near to the top of the file, `bson_buffer.h`:

```
/* A buffer */
typedef struct bson_buffer* bson_buffer_t;
/* A position in the buffer */
typedef int bson_buffer_position;

/***** THE FOLLOWING IS THE LINE YOU NEED TO INSERT ****/
int bson_buffer_get_max_size(bson_buffer_t buffer); 

 /* Allocate and return a new buffer.
 * Return NULL on allocation failure. */
bson_buffer_t bson_buffer_new(void);
```
  -
    - Run `pwd`, confirm you are still in `/Users/$(whoami)/.rbenv/versions/3.1.3/lib/ruby/gems/3.1.0/gems/bson_ext-1.5.1/ext/cbson`
    - Run `make`, which will output warnings you can ignore
    - Run `cd ../..`, i.e., go to the `bson_ext-1.5.1` directory
    - Run `gem spec ../../cache/bson_ext-1.5.1.gem --ruby > ../../specifications/bson_ext-1.5.1.gemspec`
    - Run `gem list bson_ext`, and confirm it outputs:

```
*** LOCAL GEMS ***
bson_ext (1.5.1)
```
  -
    - Change directories back to `single_cell_portal_core`
10. Run `yarn install`
11. Run `./rails_local_setup.rb` to will write out required variables into an shell env file (using your Broad username 
to determine which `vault` paths to read from).
12. Run the source command the script outputs -- this will export those needed variables into the current shell
13. Add `config/certs/localhost.crt` to your system's trusted certificates. 
  -  Automatic route (preferred), run `sudo security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain config/certs/localhost.crt`
  - Manual route (alternative): On macOS, drag the certificate file into the Keychain Access app, use the "System" keychain, and the "Certificates" category. Then left click on the newly added certificate in the Keychain Access app, click "Get Info", then toggle open the "Trust" section, then set "When using this certificate" to "Always Trust" rather than "Use System Defaults"; and ensure "Always Trust" also gets set on all other drop-down menus in the "Trust" section.
14. Avoid errors related to hot module replacement (HMR) (i.e. `Too many open files` / `net::ERR_ABORTED 500 (Internal Server Error)`) like so:
  - Run `ulimit -Sn`, confirm you see `256`
  - In your `~/.zshrc` (or `~/.bash_profile`), add:
```
# Avoid errors caused by Vite in native local SCP using many sockets, e.g.:
#   "Errno::EMFILE: Failed to open TCP connection to 127.0.0.1:3036 (Too many open files - socket(2) for "127.0.0.1" port 3036"
# More context: https://github.com/broadinstitute/single_cell_portal_core/pull/1765
ulimit -Sn 10240
```
  - Run `source ~/.zshrc` (or `source ~/.bash_profile`), to update your running shell with those changes
  - Run `ulimit -Sn` again, confirm you see `10240`
15. Run `rails s`
16. In a separate terminal, run `bin/vite dev`
17. If you are working on functionality that involves delayed jobs, like uploading data:
    * In another terminal, run the source command output in step 7
    * run `rails jobs:work`
18. You're all set!  You can now go to https://localhost:3000 and see the website.
19. Confirm you can sign in and upload a file

## REGULAR DEVELOPMENT
Adding `source <<path-to-single-cell-portal-core>>/config/secrets/.source_env.bash` to your .zschrc or .bash_profile will source the 
secrets read from Vault to each new shell, saving you the trouble of rerunning the setup process every time you open a 
new shell.  

NOTE: If you ever use the `bin/run_tests.sh` script locally, this will write out and delete any shell env files 
after completion.  You will need to run `./ruby_local_setup.rb` again to repopulate them.

Once you're all set up, you'll want to run each of the following commands in a separate terminal (or tab of your terminal):
* `rails s # Run Rails app server`
* `bin/vite dev # Run Vite -- enables HMR for reloading JS / CSS changes instantly`
* `rails jobs:work # Run Delayed Job worker, to enable Ingest Pipeline jobs that parse uploaded files`

Here's what starting up a regular development session in native local SCP looks like:

https://user-images.githubusercontent.com/1334561/223493169-13702c5a-c91d-4389-9b52-5925a43822c9.mov

## KNOWN ISSUES
1. Developing outside the docker container inherently runs more risk that your code will not work in the docker environment in staging/production.  Be careful!  If your changes are non-trivial, confirm your changes work in the containerized deploy before committing (especially changes involving package.json and/or the Gemfile)
2. You may experience difficulty toggling back and forth between containerized and non-containerized deployment, as node-sass bindings are OS-specific.  If you see an error like 'No matching version of node-sass found'
   * if this error occurs when trying to deploy in the container, fix it by deleting the `node-modules/node-sass` folder, and then rerunning the load_env_secrets process
   * if the error is when you're trying to run locally, fix it by running `npm rebuild node-sass`

## TROUBLESHOOTING  
1. If the version you specified for Ruby is not the same as the version returned from running `ruby -v`, run `which ruby` to find out what path to Ruby is being used. The path should be something like: `<user>/.rbenv/shims/ruby`. If it is not, try adding `export PATH="$HOME/.rbenv/shims:$PATH"` to your `~/.zschrc` or `~/.bash_profile` to point it at the correct path. 
2. If, after adding your certificate as a trusted certificate, `localhost:3000` still claims that the certificate is not trusted, then ensure you followed the SETUP steps that mention certificates.
3. If you need to download Xcode for your rbenv install be aware that it can take a very long time (multiple hours) and if you are a Broad employee it is recommended you download through `selfservice` from BITS.
4. If when trying to run `bundle install` you get an error like `An error occurred while installing bson_ext (1.5.1), and Bundler cannot continue...`, see steps above that mention bson_ext.
5. If you can't sign in to your local SCP, then look for "SSL_CTX_load_verify_file" in `development.log`.  E.g., run `grep -B 3 -A 2 SSL_CTX_load_verify_file log/development.log`.  If you see that error in your logs, see steps above that mention OpenSSL.
6. If your local, undockerized SCP instance erroneously instructs you to accept Terra terms of service, AND you've recently used dockerized local SCP, clean up your settings by running `bin/docker-compose-cleanup.sh`; follow the prompt to re-load environment variables for non-dockerized local and restart your local rails and vite servers.

### SEARCH
If the content below doesn't answer your question, try searching.  Beyond Google and Stack Overflow, searching this repo's issues, commits, and other files can help.  Searching in Broad Institute's Slack instance, especially #scp-implementation can also help -- e.g. enter "<your query> in:#scp-implementation" in the Slack search box.  

### HELP FROM TEAM
If the above docs and search techniques don't work, then ask for help in [#scp-implementation](https://broadinstitute.slack.com/archives/CBEHTH601).  Copy and paste relevant text from your error, and a screenshot image if it's relevant.  Please do include at least the error's text, as images can't be searched and are thus much less likely to be helpful in the future.

### AD-HOC UPDATES
Finally, if you think this doc should be updated, please edit it!  Don't feel hindered.  If you don't have a ticket that would otherwise relate, then note [SCP-5023](https://broadworkbench.atlassian.net/browse/SCP-5023) in the title of your PR to merge your ad-hoc changes.
