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

echo $(date) " - Ansible Playbook to Install Softwares - Start" >> $DEBUG_LOG
ansible-playbook $INSTALLER_HOME/experiments/azure/scripts/playbooks/install-softwares.yaml
echo $(date) " - Ansible Playbook to Install Softwares - Complete" >> $DEBUG_LOG

echo $(date) " - Ansible Playbook to get Deployment Details - Start" >> $DEBUG_LOG
ansible-playbook $INSTALLER_HOME/experiments/azure/scripts/playbooks/deployment-details.yaml
echo $(date) " - Ansible Playbook to get Deployment Details - Complete" >> $DEBUG_LOG

# Retrieve parameters from an ARM deployment
function armParm {
  # local parmOut=$(az deployment group show -g $RESOURCE_GROUP -n $DEPLOYMENT_NAME --query properties.parameters.${1})
  local parmOut=$(echo $DEPLOYMENT_PARMS | jq -r ".${1}")
  if [[ "$parmOut" == *keyVault* ]]; then
    vaultName=$(echo $parmOut | jq -r '.reference.keyVault.id' | rev | cut -d/ -f1 | rev)
    secretName=$(echo $parmOut | jq -r '.reference.secretName') 
    # FIXME - Access controls may prevent access to this KV - not sure if this will be a real-world usage scenario
    # echo "Attempting to retrieve ARM parameter '${1}' from keyvault '${vaultName}'"
    az keyvault secret show --vault-name ${vaultName} -n ${secretName} | jq -r '.value'
  else
    echo $parmOut | jq -r '.value'
  fi
}

# Retrieve value from ARM template's defined variables. Variables must be direct values and not contain
# additional inline ARM function calls.
function armVar {
  echo $DEPLOYMENT_VARS | jq -r ".variables.${1}"
}

# Retrieve secret values from Azure Key Vault. When run as part of the ARM deployment, a new Azure Key Vault
# is created and the VM's user-assigned managed identity is given "get" access on Secrets
function vaultSecret {
  vaultName=$(armParm clusterName)
  az keyvault secret show --vault-name ${vaultName} -n ${1} | jq -r '.value'
}

echo $(date) " - Get Deployment Parameters and Variables - Start" >> $DEBUG_LOG
export BOOTSTRAP_ADMIN_USERNAME=$(armParm bootstrapAdminUsername)
export OPENSHIFT_PASSWORD=$(vaultSecret openshiftPassword)
export BOOTSTRAP_SSH_PUBLIC_KEY=$(armParm bootstrapSshPublicKey)
export COMPUTE_INSTANCE_COUNT=$(armParm computeInstanceCount)
export CONTROLPLANE_INSTANCE_COUNT=$(armParm controlplaneInstanceCount)
export SUBSCRIPTION_ID=$(az account show | jq -r '.id')
export TENANT_ID=$(az account show | jq -r '.tenantId')
export AAD_APPLICATION_ID=$(armParm aadApplicationId)
export AAD_APPLICATION_SECRET=$(vaultSecret aadApplicationSecret)
export RESOURCE_GROUP_NAME=$RESOURCE_GROUP
export LOCATION=$RESOURCE_GROUP_LOCATION
export VIRTUAL_NETWORK_NAME=$(armParm virtualNetworkName)
export SINGLE_ZONE_OR_MULTI_ZONE=az
export DNS_ZONE_NAME=$(armParm dnsZoneName)
export CONTROL_PLANE_VM_SIZE=$(armParm controlplaneVmSize)
export CONTROL_PLANE_DISK_SIZE=$(armParm controlplaneDiskSize)
export CONTROL_PLANE_DISK_TYPE=$(armParm controlplaneDiskType)
export COMPUTE_VM_SIZE=$(armParm computeVmSize)
export COMPUTE_DISK_SIZE=$(armParm computeDiskSize)
export COMPUTE_DISK_TYPE=$(armParm computeDiskType)
export CLUSTER_NAME=$(armParm clusterName)
export CLUSTER_NETWORK_CIDR=$(armVar clusterNetworkCidr)
export HOST_ADDRESS_PREFIX=$(armVar hostAddressPrefix)
export VIRTUAL_NETWORK_CIDR=$(armParm virtualNetworkCIDR)
export SERVICE_NETWORK_CIDR=$(armVar serviceNetworkCidr)
export DNS_ZONE_RESOURCE_GROUP=$(armParm dnsZoneResourceGroup)
export NETWORK_RESOURCE_GROUP=$RESOURCE_GROUP
export CONTROL_PLANE_SUBNET_NAME=$(armVar controlplaneSubnetName)
export COMPUTE_SUBNET_NAME=$(armVar computeSubnetName)
export PULL_SECRET=$(vaultSecret pullSecret)
export ENABLE_FIPS=$(armVar enableFips)
export PRIVATE_OR_PUBLIC_ENDPOINTS=$(armVar privateOrPublicEndpoints)
export PRIVATE_OR_PUBLIC=$([ "$PRIVATE_OR_PUBLIC_ENDPOINTS" == private ] && echo "Internal" || echo "External")
export OPENSHIFT_USERNAME=$(armParm openshiftUsername)
export ENABLE_AUTOSCALER=$(armVar enableAutoscaler)
export OUTBOUND_TYPE=$(armVar outboundType)
export CLUSTER_RESOURCE_GROUP_NAME=$(armParm clusterResourceGroupName)
export API_KEY=$(vaultSecret apiKey)
export OPENSHIFT_VERSION=$(armParm openshiftVersion)
echo $(date) " - Get Deployment Parameters and Variables - Complete" >> $DEBUG_LOG

# Wait for cloud-init to finish
count=0
while [[ $(/usr/bin/ps xua | /usr/bin/grep cloud-init | /usr/bin/grep -v grep) ]]; do
    echo $(date) " - Waiting for cloud init to finish. Waited $count minutes. Will wait 15 mintues." >> $DEBUG_LOG
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 15 )); then
        echo $(date) " - ERROR: Timeout waiting for cloud-init to finish" >> $DEBUG_LOG
        exit 1;
    fi
done

# TODO - why do we need this?
echo $(date) " - Disable and enable repo - Start" >> $DEBUG_LOG
sudo yum update -y --disablerepo=* --enablerepo="*microsoft*"
echo $(date) " - Disable and enable repo - Complete" >> $DEBUG_LOG

if [ $? -eq 0 ]
then
    echo $(date) " - Root File System successfully extended" >> $DEBUG_LOG
else
    echo $(date) " - Root File System failed to be grown" >> $DEBUG_LOG
	  exit 20
fi

echo $(date) " - Ansible Playbook to Install OCP - Start" >> $DEBUG_LOG
ansible-playbook $INSTALLER_HOME/experiments/azure/scripts/playbooks/install-ocp.yaml
echo $(date) " - Ansible Playbook to Install OCP - Complete" >> $DEBUG_LOG

echo $(date) " - Ansible Playbook to Enable Autoscalar - Start" >> $DEBUG_LOG
ansible-playbook $INSTALLER_HOME/experiments/azure/scripts/playbooks/enable-autoscalar.yaml
echo $(date) " - Ansible Playbook to Enable Autoscalar - Complete" >> $DEBUG_LOG

echo $(date) " - Ansible Playbook to Create a User for Login to OpenShift Console - Start" >> $DEBUG_LOG
ansible-playbook $INSTALLER_HOME/experiments/azure/scripts/playbooks/create-user.yaml
echo $(date) " - Ansible Playbook to Create a User for Login to OpenShift Console - Complete" >> $DEBUG_LOG

echo $(date) " - Ansible Playbook to Setup IBM Operator Catalog - Start" >> $DEBUG_LOG
ansible-playbook $INSTALLER_HOME/experiments/azure/scripts/playbooks/install-ibm-operator-catalog.yaml"
echo $(date) " - Ansible Playbook to Setup IBM Operator Catalog - Complete" >> $DEBUG_LOG