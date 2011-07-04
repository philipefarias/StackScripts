#!/bin/bash
#
# Config a basic CouchDB server with some security
#
# Author: Philipe Farias <philipefarias@gmail.com>
#
# <udf name="user_name" label="Unprivileged User Account" />
# <udf name="user_password" label="Unprivileged User Password" />
# <udf name="user_sshkey" label="Public Key for User" default="" />
# <udf name="user_groups" label="User Groups" default="admin" />
#
# <UDF name="sshd_permitrootlogin" label="Permit SSH root login" oneof="No,Yes" default="No" />
# <UDF name="sshd_passwordauth" label="Use SSH password authentication" oneOf="Yes,No" default="Yes" example="Turn off password authentication if you have added a Public Key" />
# <UDF name="sys_hostname" Label="System hostname" default="myvps" example="Name of your server, i.e. linode1" />
#
# <udf name="couch_version" label="Apache CouchDB Version" default="1.1.0" />
# <udf name="couch_mirror" label="Apache CouchDB Package Mirror" default="mirror.atlanticmetro.net/apache" example="Paste the url till the couchdb folder." />

source <ssinclude StackScriptID="1">
source <ssinclude StackScriptID="123"> # lib-system-ubuntu

system_update

system_update_locale_en_US_UTF_8
system_update_hostname "$SYS_HOSTNAME"

# Create user account
system_add_user "$USER_NAME" "$USER_PASSWORD" "$USER_GROUPS"
if [ "$USER_SSHKEY" ]; then
    system_user_add_ssh_key "$USER_NAME" "$USER_SSHKEY"
fi

# Configure sshd
system_sshd_permitrootlogin "$SSHD_PERMITROOTLOGIN"
system_sshd_passwordauthentication "$SSHD_PASSWORDAUTH"
system_sshd_pubkeyauthentication "yes"
service ssh restart

# Install firewall and some security utilities
apt-get -y install fail2ban logcheck logcheck-database ufw

ufw default deny
ufw allow ${SSHD_PORT}
ufw enable

postfix_install_loopback_only # SS1

# Install CouchDB
source <ssinclude StackScriptID="2847">

apt-get -y install curl build-essential
build_spidermonkey

curl http://${COUCH_MIRROR}/couchdb/${COUCH_VERSION}/apache-couchdb-${COUCH_VERSION}.tar.gz | tar zxv
build_couchdb "apache-couchdb-${COUCH_VERSION}"

ufw allow 5984 # CouchDB port

# Install some good stuff
apt-get -y install bash-completion less vim wget

restartServices
