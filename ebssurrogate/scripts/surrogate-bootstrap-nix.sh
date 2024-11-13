#!/usr/bin/env bash
#
# This script creates filesystem and setups up chrooted
# enviroment for further processing. It also runs
# ansible playbook and finally does system cleanup.
#
# Adapted from: https://github.com/jen20/packer-ubuntu-zfs

set -o errexit
set -o pipefail
set -o xtrace

if [ $(dpkg --print-architecture) = "amd64" ]; 
then 
	ARCH="amd64";
else
        ARCH="arm64";
fi

function waitfor_boot_finished {
	export DEBIAN_FRONTEND=noninteractive

	echo "args: ${ARGS}"
	# Wait for cloudinit on the surrogate to complete before making progress
	while [[ ! -f /var/lib/cloud/instance/boot-finished ]]; do
	    echo 'Waiting for cloud-init...'
	    sleep 1
	done
}

function install_packages {
	# Setup Ansible on host VM
	apt-get update && sudo apt-get install software-properties-common -y
	add-apt-repository --yes --update ppa:ansible/ansible && sudo apt-get install ansible -y
	ansible-galaxy collection install community.general

	# Update apt and install required packages
	apt-get update
	apt-get install -y \
		gdisk \
		e2fsprogs \
		debootstrap \
		nvme-cli
}

function execute_playbook {

tee /etc/ansible/ansible.cfg <<EOF
[defaults]
callbacks_enabled = timer, profile_tasks, profile_roles
EOF
	# Run Ansible playbook
	#export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_DEBUG=True && export ANSIBLE_REMOTE_TEMP=/mnt/tmp 
	export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_REMOTE_TEMP=/mnt/tmp
	ansible-playbook ./ansible/playbook.yml --extra-vars '{"nixpkg_mode": true, "debpkg_mode": false, "stage2_nix": false}' # $ARGS - I think this is being not passed in correctly
}

function setup_postgesql_env {
	    # Create the directory if it doesn't exist
    sudo mkdir -p /etc/environment.d

    # Define the contents of the PostgreSQL environment file
    cat <<EOF | sudo tee /etc/environment.d/postgresql.env >/dev/null
LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
LANG="en_US.UTF-8"
LANGUAGE="en_US.UTF-8"
LC_ALL="en_US.UTF-8"
LC_CTYPE="en_US.UTF-8"
EOF
}

function setup_locale {
cat << EOF >> /etc/locale.gen
en_US.UTF-8 UTF-8
EOF

cat << EOF > /etc/default/locale
LANG="C.UTF-8"
LC_CTYPE="C.UTF-8"
EOF
	locale-gen en_US.UTF-8
}

waitfor_boot_finished
install_packages
setup_postgesql_env
setup_locale
execute_playbook

# stage 2 things
function install_nix() {
    sudo su -c "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm \
    --extra-conf \"substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com\" \
    --extra-conf \"trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=\" " -s /bin/bash root
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

}


function execute_stage2_playbook {
    sudo tee /etc/ansible/ansible.cfg <<EOF
[defaults]
callbacks_enabled = timer, profile_tasks, profile_roles
EOF
    # sed -i 's/- hosts: all/- hosts: localhost/' /tmp/ansible-playbook/ansible/playbook.yml
    # Run Ansible playbook
    export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_REMOTE_TEMP=/tmp
    ansible-playbook ./ansible/playbook.yml \
        --extra-vars '{"nixpkg_mode": false, "stage2_nix": true, "debpkg_mode": false}' \
        --extra-vars "git_commit_sha=${GIT_SHA}"
}

install_nix
execute_stage2_playbook
cloud-init clean --logs
