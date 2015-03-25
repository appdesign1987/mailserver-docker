#!/bin/bash
#
# Postfix (SMTP)
# --------------
#
# Postfix handles the transmission of email between servers
# using the SMTP protocol. It is a Mail Transfer Agent (MTA).
#
# Postfix listens on port 25 (SMTP) for incoming mail from
# other servers on the Internet. It is responsible for very
# basic email filtering such as by IP address and greylisting,
# it checks that the destination address is valid, rewrites
# destinations according to aliases, and passses email on to
# another service for local mail delivery.
#
# The first hop in local mail delivery is to Spamassassin via
# LMTP. Spamassassin then passes mail over to Dovecot for
# storage in the user's mailbox.
#
# Postfix also listens on port 587 (SMTP+STARTLS) for
# connections from users who can authenticate and then sends
# their email out to the outside world. Postfix queries Dovecot
# to authenticate users.
#
# Address validation, alias rewriting, and user authentication
# is configured in a separate setup script mail-users.sh
# because of the overlap of this part with the Dovecot
# configuration.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Install packages.

# Install postfix's packages.
#
# * `postfix`: The SMTP server.
# * `postfix-pcre`: Enables header filtering.
# * `postgrey`: A mail policy service that soft-rejects mail the first time
#   it is received. Spammers don't usually try agian. Legitimate mail
#   always will.
# * `ca-certificates`: A trust store used to squelch postfix warnings about
#   untrusted opportunistically-encrypted connections.

apt_install postfix postfix-pcre postgrey ca-certificates

# ### Basic Settings

# Set some basic settings...
#
# * Have postfix listen on all network interfaces.
# * Set our name (the Debian default seems to be "localhost" but make it our hostname).
# * Set the name of the local machine to localhost, which means xxx@localhost is delivered locally, although we don't use it.
# * Set the SMTP banner (which must have the hostname first, then anything).
tools/editconf.py /etc/postfix/main.cf \
	inet_interfaces=all \
	myhostname=$PRIMARY_HOSTNAME\
	smtpd_banner="\$myhostname ESMTP Hi, I'm a Mail-in-a-Box (Ubuntu/Postfix; see https://mailinabox.email/)" \
	mydestination=localhost

# ### Outgoing Mail

# Enable the 'submission' port 587 smtpd server and tweak its settings.
#
# * Require the best ciphers for incoming connections per http://baldric.net/2013/12/07/tls-ciphers-in-postfix-and-dovecot/.
#   By putting this setting here we leave opportunistic TLS on incoming mail at default cipher settings (any cipher is better than none).
# * Give it a different name in syslog to distinguish it from the port 25 smtpd server.
# * Add a new cleanup service specific to the submission service ('authclean')
#   that filters out privacy-sensitive headers on mail being sent out by
#   authenticated users.
tools/editconf.py /etc/postfix/master.cf -s -w \
	"submission=inet n       -       -       -       -       smtpd
	  -o syslog_name=postfix/submission
	  -o smtpd_tls_ciphers=high -o smtpd_tls_protocols=!SSLv2,!SSLv3
	  -o cleanup_service_name=authclean" \
	"authclean=unix  n       -       -       -       0       cleanup
	  -o header_checks=pcre:/etc/postfix/outgoing_mail_header_filters"

# Install the `outgoing_mail_header_filters` file required by the new 'authclean' service.
cp conf/postfix_outgoing_mail_header_filters /etc/postfix/outgoing_mail_header_filters

# Enable TLS on these and all other connections (i.e. ports 25 *and* 587) and
# require TLS before a user is allowed to authenticate. This also makes
# opportunistic TLS available on *incoming* mail.
# Set stronger DH parameters, which via openssl tend to default to 1024 bits
# (see ssl.sh).
tools/editconf.py /etc/postfix/main.cf \
	smtpd_tls_security_level=may\
	smtpd_tls_auth_only=yes \
	smtpd_tls_cert_file=$STORAGE_ROOT/ssl/ssl_certificate.pem \
	smtpd_tls_key_file=$STORAGE_ROOT/ssl/ssl_private_key.pem \
	smtpd_tls_dh1024_param_file=$STORAGE_ROOT/ssl/dh2048.pem \
	smtpd_tls_received_header=yes

# Prevent non-authenticated users from sending mail that requires being
# relayed elsewhere. We don't want to be an "open relay". On outbound
# mail, require one of:
#
# * `permit_sasl_authenticated`: Authenticated users (i.e. on port 587).
# * `permit_mynetworks`: Mail that originates locally.
# * `reject_unauth_destination`: No one else. (Permits mail whose destination is local and rejects other mail.)
tools/editconf.py /etc/postfix/main.cf \
	smtpd_relay_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination


# ### DANE

# When connecting to remote SMTP servers, prefer TLS and use DANE if available.
#
# Prefering ("opportunistic") TLS means Postfix will use TLS if the remote end
# offers it, otherwise it will transmit the message in the clear. Postfix will
# accept whatever SSL certificate the remote end provides. Opportunistic TLS
# protects against passive easvesdropping (but not man-in-the-middle attacks).
# DANE takes this a step further:
#
# Postfix queries DNS for the TLSA record on the destination MX host. If no TLSA records are found,
# then opportunistic TLS is used. Otherwise the server certificate must match the TLSA records
# or else the mail bounces. TLSA also requires DNSSEC on the MX host. Postfix doesn't do DNSSEC
# itself but assumes the system's nameserver does and reports DNSSEC status. Thus this also
# relies on our local bind9 server being present and `smtp_dns_support_level=dnssec`.
#
# The `smtp_tls_CAfile` is superflous, but it eliminates warnings in the logs about untrusted certs,
# which we don't care about seeing because Postfix is doing opportunistic TLS anyway. Better to encrypt,
# even if we don't know if it's to the right party, than to not encrypt at all. Instead we'll
# now see notices about trusted certs. The CA file is provided by the package `ca-certificates`.
tools/editconf.py /etc/postfix/main.cf \
	smtp_tls_security_level=dane \
	smtp_dns_support_level=dnssec \
	smtp_tls_CAfile=/etc/ssl/certs/ca-certificates.crt \
	smtp_tls_loglevel=2

# ### Incoming Mail

# Pass any incoming mail over to a local delivery agent. Spamassassin
# will act as the LDA agent at first. It is listening on port 10025
# with LMTP. Spamassassin will pass the mail over to Dovecot after.
#
# In a basic setup we would pass mail directly to Dovecot by setting
# virtual_transport to `lmtp:unix:private/dovecot-lmtp`.
#
tools/editconf.py /etc/postfix/main.cf virtual_transport=lmtp:[127.0.0.1]:10025

# Who can send mail to us? Some basic filters.
#
# * `reject_non_fqdn_sender`: Reject not-nice-looking return paths.
# * `reject_unknown_sender_domain`: Reject return paths with invalid domains.
# * `reject_rhsbl_sender`: Reject return paths that use blacklisted domains.
# * `permit_sasl_authenticated`: Authenticated users (i.e. on port 587) can skip further checks.
# * `permit_mynetworks`: Mail that originates locally can skip further checks.
# * `reject_rbl_client`: Reject connections from IP addresses blacklisted in zen.spamhaus.org
# * `reject_unlisted_recipient`: Although Postfix will reject mail to unknown recipients, it's nicer to reject such mail ahead of greylisting rather than after.
# * `check_policy_service`: Apply greylisting using postgrey.
#
# Notes: #NODOC
# permit_dnswl_client can pass through mail from whitelisted IP addresses, which would be good to put before greylisting #NODOC
# so these IPs get mail delivered quickly. But when an IP is not listed in the permit_dnswl_client list (i.e. it is not #NODOC
# whitelisted) then postfix does a DEFER_IF_REJECT, which results in all "unknown user" sorts of messages turning into #NODOC
# "450 4.7.1 Client host rejected: Service unavailable". This is a retry code, so the mail doesn't properly bounce. #NODOC
tools/editconf.py /etc/postfix/main.cf \
	smtpd_sender_restrictions="reject_non_fqdn_sender,reject_unknown_sender_domain,reject_rhsbl_sender dbl.spamhaus.org" \
	smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,"reject_rbl_client zen.spamhaus.org",reject_unlisted_recipient,"check_policy_service inet:127.0.0.1:10023"

# Postfix connects to Postgrey on the 127.0.0.1 interface specifically. Ensure that
# Postgrey listens on the same interface (and not IPv6, for instance).
tools/editconf.py /etc/default/postgrey \
	POSTGREY_OPTS=\"--inet=127.0.0.1:10023\"

# Increase the message size limit from 10MB to 128MB.
# The same limit is specified in nginx.conf for mail submitted via webmail and Z-Push.
tools/editconf.py /etc/postfix/main.cf \
	message_size_limit=134217728

# Allow the two SMTP ports in the firewall.

ufw_allow smtp
ufw_allow submission

# Restart services

restart_service postfix
