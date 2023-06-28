#!/bin/bash
set -ex

export INSTALLER_HOME=/mnt/openshift
mkdir -p $INSTALLER_HOME
export DEBUG_LOG=$INSTALLER_HOME/debug.log
touch $DEBUG_LOG

echo $(date) " - Updating Packages and Installing Package Dependencies" >> $DEBUG_LOG
sudo dnf update -y

echo $(date) " - Install Ansible - Start" >> $DEBUG_LOG
pip install 'ansible[azure]'
ansible-galaxy collection install azure.azcollection
pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements-azure.txt
echo $(date) " - Install Ansible - Complete" >> $DEBUG_LOG