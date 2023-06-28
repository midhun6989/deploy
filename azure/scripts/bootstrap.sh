#!/bin/bash
set -ex

export INSTALLER_HOME=/mnt/openshift
mkdir -p $INSTALLER_HOME/experiments
export DEBUG_LOG=$INSTALLER_HOME/debug.log
touch $DEBUG_LOG

echo $(date) " - Install git - Start" >> $DEBUG_LOG
sudo dnf install -y git
echo $(date) " - Install git - Complete" >> $DEBUG_LOG

echo $(date) " - Clone GitHub Repository - Start" >> $DEBUG_LOG
git clone --branch ansible-playbook https://github.com/midhun6989/experiments.git $INSTALLER_HOME/experiments
echo $(date) " - Clone GitHub Repository - Complete" >> $DEBUG_LOG

echo $(date) " - Install Ansible - Start" >> $DEBUG_LOG
sudo dnf install -y python3-pip
sudo pip3 install --upgrade pip
pip3 install "ansible==2.9.17"
pip3 install ansible[azure]
echo $(date) " - Install Ansible - Complete" >> $DEBUG_LOG

echo $(date) " - Execute Ansible Playbook - Start" >> $DEBUG_LOG
ansible-playbook $INSTALLER_HOME/experiments/azure/scripts/install-softwares.yml
echo $(date) " - Execute Ansible Playbook - Complete" >> $DEBUG_LOG