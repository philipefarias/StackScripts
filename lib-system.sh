#!/bin/bash
#
# System helper functions
#
# Author: Philipe Farias <philipefarias@gmail.com>

source <ssinclude StackScriptID="1">

function lower {
    # helper function
    echo $1 | tr '[:upper:]' '[:lower:]'
}

function setup_hostname {
  HOSTNAME=$1
  if [ -z "$HOSTNAME" ] ; then
    export HOSTNAME=get_rdns_primary_ip
  fi
  HOST=`echo $HOSTNAME | sed 's/\(\[a-z0-9\]\)*\..*/\1/'`
  echo "$HOST" >  /etc/hostname
  echo "`system_primary_ip` $HOSTNAME $HOST" >> /etc/hosts
  sed -i "s/^SET_HOSTNAME=.*/#&/" /etc/default/dhcpcd
  start hostname
}

function update_locale_en_US_UTF_8 {
  # locale-gen en_US.UTF-8
  dpkg-reconfigure locales
  update-locale LANG=en_US.UTF-8
}

function set_timezone {
  # $1 - timezone (zoneinfo file)
  ln -sf "/usr/share/zoneinfo/$1" /etc/localtime
}

function system_add_user {
  # $1 - username
  # $2 - password
  # $3 - groups
  USERNAME=`lower $1`
  PASSWORD=$2
  SUDO_GROUP=$3
  SHELL="/bin/bash"
  useradd --create-home --shell "$SHELL" --user-group --groups "$SUDO_GROUP" "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd
}

function get_user_home {
  # $1 - username
  cat /etc/passwd | grep "^$1:" | cut --delimiter=":" -f6
}

# SSH functions
function configure_sshd {
  sshd_config_set_port "$SSHD_PORT"
  sshd_config_permitrootlogin "$SSHD_PERMITROOTLOGIN"
  sshd_config_passwordauthentication "$SSHD_PASSWORDAUTH"
  sshd_config_pubkeyauthentication "$SSHD_PUBKEYAUTH"
  service ssh restart
}

function add_user_ssh_key {
    # $1 - username
    # $2 - ssh key
    USERNAME=`lower $1`
    USER_HOME=`get_user_home "$USERNAME"`
    sudo -u "$USERNAME" mkdir "$USER_HOME/.ssh"
    sudo -u "$USERNAME" touch "$USER_HOME/.ssh/authorized_keys"
    sudo -u "$USERNAME" echo "$2" >> "$USER_HOME/.ssh/authorized_keys"
    chmod 0600 "$USER_HOME/.ssh/authorized_keys"
}

function sshd_config_set_port {
  sed -i "s/Port 22/Port $1/" /etc/ssh/sshd_config
}

function sshd_config_edit_bool {
    # $1 - param name
    # $2 - Yes/No
    VALUE=`lower $2`
    if [ "$VALUE" == "yes" ] || [ "$VALUE" == "no" ]; then
        sed -i "s/^#*\($1\).*/\1 $VALUE/" /etc/ssh/sshd_config
    fi
}

function sshd_config_permitrootlogin {
    sshd_config_edit_bool "PermitRootLogin" "$1"
}

function sshd_config_passwordauthentication {
    sshd_config_edit_bool "PasswordAuthentication" "$1"
}

function sshd_config_pubkeyauthentication {
    sshd_config_edit_bool "PubkeyAuthentication" "$1"
}

function sshd_config_passwordauthentication {
    sshd_config_edit_bool "PasswordAuthentication" "$1"
}

# Email
function install_postfix {
  # $1 - root email
  # $2 - username
  postfix_install_loopback_only # SS1
  #install mail sending utilities
  apt-get -y install mailutils
  #configure root alias
  echo "root: $1" >> /etc/aliases
  echo "$2: root" >> /etc/aliases
  cat /etc/hostname > /etc/mailname
  newaliases
  sed -i "s/mydestination = localhost, localhost.localdomain, , localhost/mydestination = localhost, localhost.localdomain, $HOSTNAME/" /etc/postfix/main.cf
  service postfix restart
}

# Monit and Munin
function install_monit {
  # $1 - root email
  apt-get -y install monit
  sed -i 's/startup=0/startup=1/' /etc/default/monit
  mkdir -p /etc/monit/conf.d/
  sed -i "s/# set daemon  120/set daemon 120/" /etc/monit/monitrc
  sed -i "s/#     with start delay 240/with start delay 240/" /etc/monit/monitrc
  sed -i "s/# set logfile syslog facility log_daemon/set logfile \/var\/log\/monit.log/" /etc/monit/monitrc
  sed -i "s/# set mailserver mail.bar.baz,/set mailserver localhost/" /etc/monit/monitrc
  sed -i "s/# set eventqueue/set eventqueue/" /etc/monit/monitrc
  sed -i "s/#     basedir \/var\/monit/basedir \/var\/monit/" /etc/monit/monitrc
  sed -i "s/#     slots 100 /slots 100/" /etc/monit/monitrc
  sed -i "s/# set alert sysadm@foo.bar/set alert $1 reminder 180/" /etc/monit/monitrc
  sed -i "s/# set httpd port 2812 and/ set httpd port 2812 and/" /etc/monit/monitrc
  sed -i "s/#     use address localhost/use address localhost/" /etc/monit/monitrc
  sed -i "s/#     allow localhost/allow localhost/" /etc/monit/monitrc
  sed -i "s/# set mail-format { from: monit@foo.bar }/set mail-format { from: monit@`hostname -f` }/" /etc/monit/monitrc
  cat << EOT > /etc/monit/conf.d/system
  check system `hostname`
    if loadavg (1min) > 4 then alert
    if loadavg (5min) > 4 then alert
    if memory usage > 90% then alert
    if cpu usage (user) > 70% then alert
    if cpu usage (system) > 30% then alert
    if cpu usage (wait) > 20% then alert

check filesystem rootfs with path /
if space > 80% then alert
EOT
}

function install_munin_node {
  # $1 - node hostname
  # $2 - munin server ip
  apt-get -y install munin-node
  sed -i "s/^#host_name .*/host_name $1/" /etc/munin/munin-node.conf
  sed -i "s/^allow .*/&\nallow \^$2\$/" /etc/munin/munin-node.conf
  service munin-node restart
}
