#!/bin/bash
set -ex

echo $(date) " - Updating Packages and Installing Package Dependencies" >> $DEBUG_LOG
sudo dnf update -y

echo $(date) " - Install Ansible - Start" >> $DEBUG_LOG
pip install 'ansible[azure]'
ansible-galaxy collection install azure.azcollection
pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements-azure.txt
echo $(date) " - Install Ansible - Complete" >> $DEBUG_LOG