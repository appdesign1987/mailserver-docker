#!/bin/bash
# DNS
# -----------------------------------------------

# This script installs packages, but the DNS zone files are only
# created by the /dns/update API in the management server because
# the set of zones (domains) hosted by the server depends on the
# mail users & aliases created by the user later.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Install `nsd`, our DNS server software, and `ldnsutils` which helps
# us sign zones for DNSSEC.

# ...but first, we have to create the user because the 
# current Ubuntu forgets to do so in the .deb
# (see issue #25 and https://bugs.launchpad.net/ubuntu/+source/nsd/+bug/1311886)
if id nsd > /dev/null 2>&1; then
	true #echo "nsd user exists... good"; #NODOC
else
	useradd nsd;
fi

# Okay now install the packages.
#
# * nsd: The non-recursive nameserver that publishes our DNS records.
# * ldnsutils: Helper utilities for signing DNSSEC zones.
# * openssh-client: Provides ssh-keyscan which we use to create SSHFP records.

apt_install nsd ldnsutils openssh-client

# Prepare nsd's configuration.

mkdir -p /var/run/nsd

# Create DNSSEC signing keys.

mkdir -p "$STORAGE_ROOT/dns/dnssec";

# TLDs don't all support the same algorithms, so we'll generate keys using a few
# different algorithms. RSASHA1-NSEC3-SHA1 was possibly the first widely used
# algorithm that supported NSEC3, which is a security best practice. However TLDs
# will probably be moving away from it to a a SHA256-based algorithm.
#
# Supports `RSASHA1-NSEC3-SHA1` (didn't test with `RSASHA256`):
#
#  * .info
#  * .me
#
# Requires `RSASHA256`
#
#  * .email
#  * .guide
#
# Supports `RSASHA256` (and defaulting to this)
#
#  * .fund

FIRST=1 #NODOC
for algo in RSASHA1-NSEC3-SHA1 RSASHA256; do
if [ ! -f "$STORAGE_ROOT/dns/dnssec/$algo.conf" ]; then
	if [ $FIRST == 1 ]; then
		echo "Generating DNSSEC signing keys. This may take a few minutes..."
		FIRST=0 #NODOC
	fi

	# Create the Key-Signing Key (KSK) (with `-k`) which is the so-called
	# Secure Entry Point. The domain name we provide ("_domain_") doesn't
	#  matter -- we'll use the same keys for all our domains.
	#
	# `ldns-keygen` outputs the new key's filename to stdout, which
	# we're capturing into the `KSK` variable.
	KSK=$(umask 077; cd $STORAGE_ROOT/dns/dnssec; ldns-keygen -a $algo -b 2048 -k _domain_);

	# Now create a Zone-Signing Key (ZSK) which is expected to be
	# rotated more often than a KSK, although we have no plans to
	# rotate it (and doing so would be difficult to do without
	# disturbing DNS availability.) Omit `-k` and use a shorter key length.
	ZSK=$(umask 077; cd $STORAGE_ROOT/dns/dnssec; ldns-keygen -a $algo -b 1024 _domain_);

	# These generate two sets of files like:
	#
	# * `K_domain_.+007+08882.ds`: DS record normally provided to domain name registrar (but it's actually invalid with `_domain_`)
	# * `K_domain_.+007+08882.key`: public key
	# * `K_domain_.+007+08882.private`: private key (secret!)

	# The filenames are unpredictable and encode the key generation
	# options. So we'll store the names of the files we just generated.
	# We might have multiple keys down the road. This will identify
	# what keys are the current keys.
	cat > $STORAGE_ROOT/dns/dnssec/$algo.conf << EOF;
KSK=$KSK
ZSK=$ZSK
EOF
fi

	# And loop to do the next algorithm...
done

# Force the dns_update script to be run every day to re-sign zones for DNSSEC
# before they expire. When we sign zones (in `dns_update.py`) we specify a
# 30-day validation window, so we had better re-sign before then.
cat > /etc/cron.daily/mailinabox-dnssec << EOF;
#!/bin/bash
# Mail-in-a-Box
# Re-sign any DNS zones with DNSSEC because the signatures expire periodically.
`pwd`/tools/dns_update
EOF
chmod +x /etc/cron.daily/mailinabox-dnssec

# Permit DNS queries on TCP/UDP in the firewall.

ufw_allow domain

