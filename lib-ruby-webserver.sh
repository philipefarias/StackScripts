#!/bin/bash
#
# Helper functions to install and configure a ruby webserver
#
# Author: Philipe Farias <philipefarias@gmail.com>

## Install nginx stable from ppa
function login_as {
  # $1 - username to login as
  if [ "$1" != "$LOGNAME" ]; then
    su "$1" -l
  fi
}

function install_nginx {
  apt-get -y install python-software-properties
  add-apt-repository -y ppa:nginx/stable
  apt-get update

  apt-get -y install nginx
}

function configure_ruby_environment_for_user {
  # $1 - username
  # $2 - ruby version/type
  apt-get -y install build-essential openssl libreadline6 libreadline6-dev curl git-core zlib1g zlib1g-dev libssl-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt-dev autoconf libc6-dev ncurses-dev automake libtool bison subversion pkg-config

  login_as "$1"

  # Install RVM and Ruby
  echo 'rvm_path="$HOME/.rvm"' >> ~/.rvmrc
  curl -L get.rvm.io | sudo bash -s stable # multi-user install
  source "$HOME/.rvm/scripts/rvm"
  command rvm install "$2"
  command rvm "$2" --default

  GEMRC=<<EOD
---
install: --no-rdoc --no-ri
update: --no-rdoc --no-ri
EOD

  echo "$GEMRC" >> ~/.gemrc

  # Logout to root
  logout

  # Following steps for RVM multi-user install
  # Add user to rvm group
  usermod -a -G rvm $1
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

  mkdir -p $DEPLOY_PATH
  chown $USERNAME:$USERNAME $DEPLOY_PATH

  login_as "$USERNAME"

  mkdir -p "$GIT_PATH"
  cd "$GIT_PATH"
  git init --bare
  cd -

  configure_git_post_receive_hook "$APP_NAME" "$APP_URL" "$GIT_PATH" "$DEPLOY_PATH"

  # Logout to root
  logout

  configure_nginx "$APP_NAME" "$APP_URL" "$DEPLOY_PATH"
}

function configure_git_post_receive_hook {
  # $1 - app name
  # $2 - app url
  # $3 - git path
  # $4 - deploy path
  APP_NAME=$1
  APP_URL=$2
  GIT_PATH=$3
  DEPLOY_PATH=$4

  GIT_POST_RECEIVE_HOOK=<<EOD
#!/bin/sh

message() {
echo "-----> \$1"
}

exit_with_error() {
message "An error has occurred!!!"
exit 1
}

message "Preparing to deploy"

APP_NAME="$APP_NAME"
export RACK_ENV="production"

\# Load RVM into a shell session *as a function*
if [[ -s "\$HOME/.rvm/scripts/rvm" ]] ; then
\# First try to load from a user install
source "\$HOME/.rvm/scripts/rvm"
elif [[ -s "/usr/local/rvm/scripts/rvm" ]] ; then
\# Then try to load from a root install
source "/usr/local/rvm/scripts/rvm"
else
printf "ERROR: An RVM installation was not found.\n"
fi

message "Deploying $APP_NAME"

GIT_WORK_TREE="$DEPLOY_PATH" git checkout -f

cd "\$GIT_WORK_TREE"
rvm default || exit_with_error
bundle install --deployment || exit_with_error
cd -
EOD

  echo "$GIT_POST_RECEIVE_HOOK" >> "$GIT_PATH/hooks/post-receive"
  chmod +x "$GIT_PATH/hooks/post-receive"
}

function configure_nginx {
  # $1 - app name
  # $2 - app url
  # $3 - deploy path
  APP_NAME=$1
  APP_URL=$2
  DEPLOY_PATH=$3

  NGINX_SITE_CONF=<<EOD
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

  rm "/etc/nginx/sites-enabled/default"
  echo "$NGINX_SITE_CONF" >> "/etc/nginx/sites-available/$APP_NAME.conf"
  cd "/etc/nginx/sites-enabled"
  ln -fs "/etc/nginx/sites-available/$APP_NAME.conf" "."
}