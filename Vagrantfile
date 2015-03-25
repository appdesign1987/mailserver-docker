# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu14.04"
  config.vm.box_url = "http://cloud-images.ubuntu.com/vagrant/trusty/current/trusty-server-cloudimg-amd64-vagrant-disk1.box"

  # Network config: Since it's a mail server, the machine must be connected
  # to the public web. However, we currently don't want to expose SSH since
  # the machine's box will let anyone log into it. So instead we'll put the
  # machine on a private network.
  config.vm.hostname = "mailinabox"
  config.vm.network "private_network", ip: "192.168.50.4"

  config.vm.provision :shell, :inline => <<-SH
	# Set environment variables so that the setup script does
	# not ask any questions during provisioning. We'll let the
	# machine figure out its own public IP and it'll take a
	# subdomain on our justtesting.email domain so we can get
	# started quickly.
    export NONINTERACTIVE=1
    export PUBLIC_IP=auto
    export PUBLIC_IPV6=auto
    export PRIMARY_HOSTNAME=auto-easy
    export CSR_COUNTRY=US
    #export SKIP_NETWORK_CHECKS=1

    # Start the setup script.
    cd /vagrant
    setup/start.sh
SH
end
