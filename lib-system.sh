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

function set_hostname {
  HOSTNAME=$1
  if [ -z "$HOSTNAME" ] ; then
    export HOSTNAME=get_rdns_primary_ip
  fi
  HOST=`echo $HOSTNAME | sed 's/\(\[a-z0-9\]\)*\..*/\1/'`
  HOSTS_LINE="`system_primary_ip`\t$HOSTNAME\t$HOST"
  echo "$HOST" > /etc/hostname
  sed -i "s/^127\.0\.0\.1 .*$/&\n$HOSTS_LINE/" /etc/hosts
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
  dpkg-reconfigure --frontend noninteractive tzdata
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
  #lock out root
  passwd -l root
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
  touch /tmp/restart-ssh
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
  touch /tmp/restart-postfix
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
  touch /tmp/restart-monit
}

function install_munin_node {
  # $1 - node hostname
  # $2 - munin server ip
  apt-get -y install munin-node
  sed -i "s/^#host_name .*/host_name $1/" /etc/munin/munin-node.conf
  sed -i "s/^allow .*$/&\nallow \^$2\$/ ; /^allow \^\d*/ s/[.]/\\\&/g ; /^allow \^\d*/ s/\\\\\\\/\\\/g" /etc/munin/munin-node.conf
  touch /tmp/restart-munin-node
}

# Security tools
function install_security_tools {
  apt-get -y install chkrootkit rkhunter fail2ban logcheck logcheck-database logwatch ufw

  cp /usr/share/logwatch/default.conf/logwatch.conf /etc/logwatch/conf/
  mkdir /var/cache/logwatch

  rkhunter --propupd
}

function set_conf_value {
  # $1 - conf file
  # $2 - key
  # $3 - value
  sed -i "s/^\($2[ ]*=[ ]*\).*/\1$3/" $1
}

function configure_chkrootkit {
  CONF=/etc/chkrootkit.conf
  test -f $CONF || exit 0

  set_conf_value $CONF "RUN_DAILY" "\"true\""
}

function configure_rkhunter {
  CONF=/etc/rkhunter.conf
  test -f $CONF || exit 0

  set_conf_value $CONF "MAIL-ON-WARNING" "\"root\""
  sed -i "/ALLOWHIDDENDIR=\/dev\/.udev$/ s/^#//" $CONF
  # Disabling tests for kernel modules, Linode kernel doens't have any modules loaded
  sed -i "/^DISABLE_TESTS=.*/ s/\"$/ os_specific\"/" $CONF
}

function configure_logcheck {
  # Stop the message flood about UFW blocking SYN packets
  UFW_BLOCK_REGEX="^\w{3} [ :[:digit:]]{11} [._[:alnum:]-]+ kernel: \[UFW BLOCK\] IN=[[:alnum:]]+ OUT= MAC=[:[:xdigit:]]+ SRC=[.[:digit:]]{7,15} DST=[.[:digit:]]{7,15} LEN=[[:digit:]]+ TOS=0x[[:xdigit:]]+ PREC=0x[[:xdigit:]]+ TTL=[[:digit:]]+ ID=[[:digit:]]+ (DF )?PROTO=TCP SPT=[[:digit:]]+ DPT=[[:digit:]]+ WINDOW=[[:digit:]]+ RES=0x[[:xdigit:]]+ SYN URGP=[[:digit:]]+$"
  echo $UFW_BLOCK_REGEX >> /etc/logcheck/ignore.d.server/local
}

function configure_logwatch {
  CONF=/etc/logwatch/conf/logwatch.conf
  test -f $CONF || exit 0

  set_conf_value $CONF "Output" "mail"
  set_conf_value $CONF "Format" "html"
  set_conf_value $CONF "Detail" "Med"
}

function configure_ufw {
  # $1, $2, $3... - ports to allow
  ufw logging on
  ufw default deny

  while [ $# -gt 0 ]; do
    ufw allow $1
    shift
  done

  ufw enable
}

# Utility
function restart_services {
  # restarts services that have a file in /tmp/needs-restart/
  for service in $(ls /tmp/restart-* | cut -d- -f2-10); do
      service $service restart
      rm -f /tmp/restart-$service
  done
}
