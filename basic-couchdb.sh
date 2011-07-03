#!/bin/bash
#
# Config a basic CouchDB server with some security
#
# Author: Philipe Farias <philipefarias@gmail.com>
#
# <udf name="user_name" label="Unprivileged User Account" />
# <udf name="user_password" label="Unprivileged User Password" />
# <udf name="user_sshkey" label="Public Key for User" default="" />
#
# <udf name="sshd_port" label="SSH Port" default="22" />
# <udf name="sshd_protocol" label="SSH Protocol" oneOf="1,2,1 and 2" default="2" />
# <udf name="sshd_permitroot" label="SSH Permit Root Login" oneof="No,Yes" default="No" />
# <udf name="sshd_passwordauth" label="SSH Password Authentication" oneOf="No,Yes" default="No" />
# <udf name="sshd_group" label="SSH Allowed Groups" default="sshusers" example="List of groups seperated by spaces" />
#
# <udf name="sudo_usergroup" label="Usergroup to use for Admin Accounts" default="wheel" />
# <udf name="sudo_passwordless" label="Passwordless Sudo" oneof="Require Password,Do Not Require Password", default="Require Password" />
#
# <udf name="couch_version" label="Apache CouchDB Version" default="1.1.0" />
# <udf name="couch_mirror" label="Apache CouchDB Package Mirror" default="mirror.atlanticmetro.net/apache" example="Paste the url till the couchdb folder." />

source <ssinclude StackScriptID="1">
source <ssinclude StackScriptID="165">

apt-get -y install ufw

ufw default deny
ufw allow ${SSHD_PORT}
ufw enable

# Install CouchDB
source <ssinclude StackScriptID="2847">

apt-get -y install curl build-essential
build_spidermonkey

curl http://${COUCH_MIRROR}/couchdb/${COUCH_VERSION}/apache-couchdb-${COUCH_VERSION}.tar.gz | tar zxv
build_couchdb "apache-couchdb-${COUCH_VERSION}"

ufw allow 5984 # CouchDB port

# Install some good stuff
apt-get -y install bash-completion less vim wget
