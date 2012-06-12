#!/bin/bash
#
# Helper functions to build CouchDB and SpiderMonkey
#
# Depends on curl and build-essential:
#   apt-get install curl build-essential
#
# Author: Philipe Farias <philipefarias@gmail.com>
#
# Script based on the CouchDB wiki:
# - http://wiki.apache.org/couchdb/Installing_on_Ubuntu
# - http://wiki.apache.org/couchdb/Installing_SpiderMonkey

## Download and build SpiderMonkey from source
function build_spidermonkey {
  curl http://ftp.mozilla.org/pub/mozilla.org/js/js185-1.0.0.tar.gz | tar zxv
  cd js-1.8.5/js/src
  make BUILD_OPT=1 -f Makefile.ref
  make BUILD_OPT=1 JS_DIST=/usr/local -f Makefile.ref export
  cd -
}

## Install CouchDB dependecies then build CouchDB
function build_couchdb {
  # $1 - path to couchdb source
  # $2 - installation tree prefix
  apt-get -y build-dep couchdb

  couch_prefix=$2

  cd $1
  ./configure --prefix=${couch_prefix}
  make && make install
  cd -

  # Add couchdb user account
  useradd -d ${couch_prefix}/var/lib/couchdb couchdb

  # Change file ownership from root to couchdb user and adjust permissions
  chown -R couchdb: ${couch_prefix}/var/lib/couchdb \
    ${couch_prefix}/var/log/couchdb \
    ${couch_prefix}/var/run/couchdb \
    ${couch_prefix}/etc/couchdb
  chmod 0770 ${couch_prefix}/var/lib/couchdb/ \
    ${couch_prefix}/var/log/couchdb/ \
    ${couch_prefix}/var/run/couchdb/
  chmod 664 ${couch_prefix}/etc/couchdb/*.ini
  chmod 775 ${couch_prefix}/etc/couchdb/*.d

  if [ -n "$couch_prefix" -a "$couch_prefix" != "/" ]
  then
    # Configure logrotate
    ln -s ${couch_prefix}/etc/logrotate.d/couchdb /etc/logrotate.d/couchdb
    # Configure the init script
    ln -sf ${couch_prefix}/etc/init.d/couchdb /etc/init.d/couchdb
  fi

  # Start couchdb
  service couchdb start
  # Start couchdb on system start
  update-rc.d couchdb defaults

  # Verify couchdb is running
  sleep 2 # must wait a little...
  curl http://127.0.0.1:5984/
  # {"couchdb":"Welcome","version":"1.1.1"}
}

function set_local_couchdb_port {
  # $1 - port number
  # $2 - couch installation prefix
  sed -i "/port[ ]*=/ s/^.*$/port = $1/" $2/etc/couchdb/local.ini
}

function set_local_couchdb_bind_address {
  # $1 - ip address
  # $2 - couch installation prefix
  sed -i "/bind_address[ ]*=/ s/^.*$/bind_address = $1/" $2/etc/couchdb/local.ini
}

function set_couchdb_admin_user {
  # $1 - couchdb host
  # $2 - username
  # $3 - password
  curl -X PUT $1/_config/admins/$2 -d "\"$3\""
}

function set_local_couchdb_require_valid_user {
  # $1 - true/false
  # $2 - couch installation prefix
  sed -i "s/^;[ ]*\(WWW-Authenticate[ ]*=.*\)$/\1/" $2/etc/couchdb/local.ini
  sed -i "s/^;[ ]*\(require_valid_user[ ]*=\)\(.*\)$/\1 $1/" $2/etc/couchdb/local.ini
}
