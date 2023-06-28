#!/bin/bash
set -ex

export INSTALLER_HOME=/mnt/openshift
mkdir -p $INSTALLER_HOME
export DEBUG_LOG=$INSTALLER_HOME/debug.log
touch $DEBUG_LOG

echo $(date) " - Updating Packages and Installing Package Dependencies" >> $DEBUG_LOG
sudo dnf update -y

echo $(date) " - Install Ansible - Start" >> $DEBUG_LOG
sudo dnf install -y python3-pip
sudo pip3 install --upgrade pip
pip3 install "ansible==2.9.17"
pip3 install ansible[azure]
echo $(date) " - Install Ansible - Complete" >> $DEBUG_LOG

echo $(date) " - Install Podman - Start" >> $DEBUG_LOG
ansible-playbook install-softwares.yml
echo $(date) " - Install Podman - Complete" >> $DEBUG_LOG