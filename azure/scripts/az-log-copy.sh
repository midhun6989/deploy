#!/bin/bash
# Script to copy OpenShift installation log files from Bootstrap VM to Azure Blob Storage
# Execution Steps
# 1. Copy this file contents and create a script log-copy.sh in the Bootstrap VM ---> vi log-copy.sh
# 2. Provide execute permission to the script file ---> chmod u+x log-copy.sh
# 3. Generate a SAS Token from the Storage Account Container with Write permission ---> Refer https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10#option-2-use-a-sas-token
# 4. Execute the script by giving the SAS Token as an argument ---> sh log-copy.sh "<SAS Token>"

# Download and extract AzCopy
wget https://aka.ms/downloadazcopy-v10-linux
tar -xvf downloadazcopy-v10-linux

# Move AzCopy to bin
sudo rm -f /usr/bin/azcopy
sudo cp ./azcopy_linux_amd64_*/azcopy /usr/bin/
sudo chmod 755 /usr/bin/azcopy

# Get the files to copy
cp /mnt/openshift/openshiftfourx/.openshift_install.log  openshift_install.log
cp /var/log/azure/custom-script/handler.log handler.log

# Zip the file and copy to Blob
zip openshift-logs.zip openshift_install.log handler.log
azcopy copy openshift-logs.zip $1

# Clean up
rm -f downloadazcopy-v10-linux wget-log openshift_install.log handler.log openshift-logs.zip
rm -rf azcopy_linux_amd64_*
