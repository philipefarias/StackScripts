#!/bin/bash
#
# Config a basic CouchDB server with some security
#
# Author: Philipe Farias <philipefarias@gmail.com>
#
# <udf name="user_name" label="User Account" />
# <udf name="user_password" label="User Password" />
# <udf name="user_sshkey" label="Public Key for User" default="" />
#
# <udf name="sshd_port" label="SSH Port" default="22" />
# <udf name="hostname" label="System Hostname" default="myvps" example="Name of your server, i.e. linode1" />
# <udf name="timezone" label="System Timezone" default="" example="Zoneinfo file on the server, i.e. America/Sao_Paulo" />
# <udf name="root_email" label="Root Email" />
#
# <udf name="munin_server_ip" label="Munin Server IP" default="127.0.0.1" />
#
# <udf name="couch_mirror" label="Apache CouchDB Package Mirror" default="mirror.atlanticmetro.net/apache" example="Paste the url till the couchdb folder." />
# <udf name="couch_user" label="CouchDB Admin User" default="admin" />
# <udf name="couch_password" label="CouchDB Admin Password" />

source <ssinclude StackScriptID="1">
source <ssinclude StackScriptID="2865"> # lib-system

system_update
update_locale_en_US_UTF_8

set_hostname "$HOSTNAME"
set_timezone "$TIMEZONE"

# Create user account
USER_GROUPS="admin"
system_add_user "$USER_NAME" "$USER_PASSWORD" "$USER_GROUPS"
if [ "$USER_SSHKEY" ]; then
    add_user_ssh_key "$USER_NAME" "$USER_SSHKEY"
fi

# Configure sshd
SSHD_PERMITROOTLOGIN="no"
SSHD_PASSWORDAUTH="no"
SSHD_PUBKEYAUTH="yes"
configure_sshd

# Simple 'just to send' email server
install_postfix "$ROOT_EMAIL" "$USER_NAME"

# Install CouchDB
source <ssinclude StackScriptID="2847">
COUCH_VERSION="1.1.0"
COUCH_BIND_ADDRESS="0.0.0.0"
COUCH_PORT="5984"
COUCH_HOST="http://$COUCH_BIND_ADDRESS:$COUCH_PORT"
curl http://${COUCH_MIRROR}/couchdb/${COUCH_VERSION}/apache-couchdb-${COUCH_VERSION}.tar.gz | tar zxv
apt-get -y install curl build-essential

build_spidermonkey
build_couchdb "apache-couchdb-${COUCH_VERSION}"

set_local_couchdb_port "$COUCH_PORT"
set_local_couchdb_bind_address "$COUCH_BIND_ADDRESS"
set_couchdb_admin_user "$COUCH_HOST" "$COUCH_USER" "$COUCH_PASSWORD"
set_local_couchdb_require_valid_user "true"

# Monitoring tools
install_monit "$ROOT_EMAIL"
install_munin_node "$HOSTNAME" "$MUNIN_SERVER_IP"

# Some good stuff
apt-get -y install bash-completion less vim wget

# Security tools
install_security_tools
configure_chkrootkit
configure_rkhunter
configure_logwatch
configure_ufw "$SSHD_PORT" "$COUCH_PORT" "munin"

# Send info message
if [ -n "$ROOT_EMAIL" ]; then
  vps_hostname="`cat /etc/hostname`"
  reverse_dns="`get_rdns_primary_ip`"
  mail -s "Your Linode VPS "$vps_hostname" is configured" "$ROOT_EMAIL" <<EOD
Hi,

Your Linode VPS configuration is completed.

SSH Access:
ssh://$USER_NAME@$reverse_dns

CouchDB:
http://$reverse_dns:$COUCH_PORT/

Your firewall status:
---
`ufw status`
---

Thanks for using this StackScript. Follow http://github.com/philipefarias/StackScripts for updates.

--
root
Linode VPS "$vps_hostname"
EOD
fi

sleep 2
reboot
