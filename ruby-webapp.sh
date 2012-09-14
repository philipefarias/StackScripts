#!/bin/bash
#
# Config a web server for Ruby apps
#
# Author: Philipe Farias <philipefarias@gmail.com>
#
# <udf name="user_name" label="User Account" />
# <udf name="user_password" label="User Password" />
# <udf name="user_sshkey" label="Public Key for User" default="" />
#
# <udf name="sshd_port" label="SSH Port" default="22" />
# <udf name="hostname" label="System Hostname" default="" example="Name of your server, i.e. linode1. Leave it blank to use Linode reverse DNS." />
# <udf name="timezone" label="System Timezone" default="" example="Zoneinfo file on the server, i.e. America/Sao_Paulo" />
# <udf name="root_email" label="Root Email" />
#
# <udf name="app_name" label="App Name" />
# <udf name="app_url" label="App URL" default="app_name.domain.com" example="Web address to be set in the webserver" />
# <udf name="ruby_version" label="Ruby Version" default="1.9.3" example="Default Ruby version to be installed with RVM" />

source <ssinclude StackScriptID="1">
source <ssinclude StackScriptID="2865"> # lib-system

system_update

#fix_page_allocation_error

update_locale_en_US_UTF_8

set_hostname "$HOSTNAME"
set_timezone "$TIMEZONE"

# Create user account
USER_GROUPS="sudo"
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

# Configure webserver
install_nginx
configure_ruby_webapp "$USER_NAME" "$APP_NAME" "$APP_URL" "$RUBY_VERSION"

# Monitoring tools
#install_monit "$ROOT_EMAIL"

# Some good stuff
apt-get -y install bash-completion less vim wget

# Security tools
install_security_tools
configure_chkrootkit
configure_rkhunter
configure_ufw "$SSHD_PORT" "http" "https"

# Send info message
if [ -n "$ROOT_EMAIL" ]; then
  vps_hostname="`cat /etc/hostname`"
  reverse_dns="`get_rdns_primary_ip`"
  mail -s "Your Linode VPS "$vps_hostname" is configured" "$ROOT_EMAIL" <<EOD
Hi,

Your Linode VPS configuration is completed.

SSH Access:
ssh://$USER_NAME@$reverse_dns

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

restart_services
