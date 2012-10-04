#!/bin/bash
#
# Helper functions to install and configure a ruby webserver
#
# Author: Philipe Farias <philipefarias@gmail.com>

## Install nginx stable from ppa
function install_nginx {
  apt-get -y install python-software-properties
  add-apt-repository -y ppa:nginx/stable
  apt-get update

  apt-get -y install nginx
}

function configure_ruby_environment_for_user {
  # $1 - username
  # $2 - ruby version/type
  USERNAME=$1
  RUBY_VERSION=$2

  apt-get -y install build-essential openssl libreadline6 libreadline6-dev curl git-core zlib1g zlib1g-dev libssl-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt-dev autoconf libc6-dev ncurses-dev automake libtool bison subversion pkg-config

  # Install RVM and Ruby
  su $USERNAME -l -c "curl -L get.rvm.io" | bash -s stable # multi-user install

  # Following steps for RVM multi-user install
  # Add user to rvm group
  usermod -a -G rvm $USERNAME

  su $USERNAME -l -c "command rvm install $RUBY_VERSION ; rvm $RUBY_VERSION --default"

  su $USERNAME -l -c "cat >~/.gemrc <<EOD
---
install: --no-rdoc --no-ri
update: --no-rdoc --no-ri
EOD"
}

function configure_ruby_webapp {
  # $1 - username
  # $2 - webapp name
  # $3 - webapp url(s)
  # $4 - ruby version
  USERNAME=$1
  APP_NAME=$2
  APP_URL=$3
  GIT_PATH="/home/$USERNAME/apps/$APP_NAME.git"
  DEPLOY_PATH="/var/www/$APP_NAME"

  configure_ruby_environment_for_user "$USERNAME" "$4"

  mkdir -p "$DEPLOY_PATH"
  mkdir -p "$GIT_PATH"
  chown -R $USERNAME:$USERNAME "$DEPLOY_PATH" "$GIT_PATH"

  su $1 -l -c "cd '$GIT_PATH'; git init --bare; touch hooks/post-receive"
  configure_git_post_receive_hook "$APP_NAME" "$GIT_PATH" "$DEPLOY_PATH"

  configure_nginx "$APP_NAME" "$APP_URL" "$DEPLOY_PATH"
}

function configure_git_post_receive_hook {
  # $1 - app name
  # $2 - git path
  # $3 - deploy path
  APP_NAME=$1
  GIT_PATH=$2
  DEPLOY_PATH=$3

  cat >"$GIT_PATH/hooks/post-receive" <<EOD
#!/bin/bash

message() {
    echo "-----> \$1"
}

exit_with_error() {
    message "An error has occurred!!!"
    echo
    exit 1
}

echo
message "Preparing to deploy"

# Load RVM into a shell session *as a function*
if [[ -s "\$HOME/.rvm/scripts/rvm" ]] ; then
    # First try to load from a user install
    source "\$HOME/.rvm/scripts/rvm"
elif [[ -s "/usr/local/rvm/scripts/rvm" ]] ; then
    # Then try to load from a root install
    source "/usr/local/rvm/scripts/rvm"
else
    printf "ERROR: An RVM installation was not found.\\n" && exit_with_error
fi
rvm default || exit_with_error

export RACK_ENV="production"

APP_NAME="$APP_NAME"
DEPLOY_PATH="$DEPLOY_PATH"
GIT_VERSION=\$(git --version | cut -d ' ' -f 3)
RVM_VERSION=\$(rvm --version | grep "rvm" | tr -s ' ' | cut -d ' ' -f 2,3)

message "Checking out files to \$DEPLOY_PATH with git \$GIT_VERSION"
GIT_WORK_TREE="\$DEPLOY_PATH" git checkout -f

cd "\$DEPLOY_PATH"
RUBY_VERSION=\$(ruby --version)
BUNDLER_VERSION=\$(bundle --version | cut -d ' ' -f 3)

echo "Using rvm \$RVM_VERSION"
echo "Using \$RUBY_VERSION"
echo "Rack environment set to \$RACK_ENV"

message "Installing gems with Bundler \$BUNDLER_VERSION"
bundle install --without development:test --path vendor/bundle --binstubs bin/ --deployment || exit_with_error
rvmsudo ./bin/foreman export upstart /etc/init -a "\$APP_NAME" -u deployer
message "Restarting application" && sudo restart "\$APP_NAME"

message "Deploy complete!"
echo
EOD

  chmod +x "$GIT_PATH/hooks/post-receive"
}

function configure_nginx {
  # $1 - app name
  # $2 - app url
  # $3 - deploy path
  APP_NAME=$1
  APP_URL=$2
  DEPLOY_PATH=$3

  rm "/etc/nginx/sites-enabled/default"
  cat >"/etc/nginx/sites-available/$APP_NAME.conf" <<EOD
upstream $APP_NAME {
  server unix:/var/run/$APP_NAME.sock fail_timeout=0;
}

server {
  listen 80;
  server_name $APP_URL;
  root $DEPLOY_PATH/public;
  try_files \$uri/index.html \$uri @$APP_URL;
  location / {
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Host \$http_host;
    proxy_pass http://$APP_NAME;
  }
  error_page 500 502 503 504 /500.html;
}
EOD

  cd "/etc/nginx/sites-enabled"
  ln -fs "/etc/nginx/sites-available/$APP_NAME.conf" "."
}
