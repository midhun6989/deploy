#!/bin/bash
set -ex

export INSTALLER_HOME=/mnt/openshift
mkdir -p $INSTALLER_HOME
export DEBUG_LOG=$INSTALLER_HOME/debug.log
touch $DEBUG_LOG

echo $(date) " - Updating Packages and Installing Package Dependencies" >> $DEBUG_LOG
sudo dnf update -y

echo $(date) " - Install Azure CLI, JQ and GIT - Start" >> $DEBUG_LOG
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
sudo dnf install -y azure-cli jq git
echo $(date) " - Install Azure CLI, JQ and GIT - Complete" >> $DEBUG_LOG

echo $(date) " - Azure CLI Login" >> $DEBUG_LOG
az login --identity

echo $(date) " - ############### Deploy Script - Start ###############" >> $DEBUG_LOG

# FIXME - if the user-assigned identity is given a scope at the subscription level, then the command below will
# fail because multiple resource groups will be listed
RESOURCE_GROUP=$(az group list --query [0].name -o tsv)
RESOURCE_GROUP_LOCATION=$(az group show -g $RESOURCE_GROUP --query location -o tsv)

# FIXME this may still fail if you re-use a resource group that may have a resource with bootstrap.sh in the name.
# Instead, if we set a unique bootnode name, then we can use the 'hostname' command and the filter below
# To find the exact ARM Deployment that created this boot node!
echo $(date) " - Get Deployment Details" >> $DEBUG_LOG
DEPLOYMENT_NAME=$(az deployment group list -g $RESOURCE_GROUP | jq -r 'map(select(.properties.dependencies[].resourceName | contains("bootstrap.sh"))) | .[] .name')
DEPLOYMENT_PARMS=$(az deployment group show -g $RESOURCE_GROUP -n $DEPLOYMENT_NAME --query properties.parameters)
DEPLOYMENT_VARS=$(az deployment group export -g $RESOURCE_GROUP -n $DEPLOYMENT_NAME)

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

echo $(date) " - Install Podman - Start" >> $DEBUG_LOG
yum install -y podman
echo $(date) " - Install Podman - Complete" >> $DEBUG_LOG

echo $(date) " - Install httpd-tools - Start" >> $DEBUG_LOG
yum install -y httpd-tools
echo $(date) " - Install httpd-tools - Complete" >> $DEBUG_LOG

echo $(date) " - Download Binaries - Start" >> $DEBUG_LOG
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-$OPENSHIFT_VERSION/openshift-install-linux.tar.gz"
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-$OPENSHIFT_VERSION/openshift-client-linux.tar.gz"
chown $BOOTSTRAP_ADMIN_USERNAME:$BOOTSTRAP_ADMIN_USERNAME $INSTALLER_HOME
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "tar -xvf openshift-install-linux.tar.gz -C $INSTALLER_HOME"
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "sudo tar -xvf openshift-client-linux.tar.gz -C /usr/bin"
chmod +x /usr/bin/kubectl
chmod +x /usr/bin/oc
chmod +x $INSTALLER_HOME/openshift-install
echo $(date) " - Download Binaries - Complete" >> $DEBUG_LOG

echo $(date) " - Setup Azure Credentials for OCP - Start" >> $DEBUG_LOG
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "mkdir -p /home/$BOOTSTRAP_ADMIN_USERNAME/.azure"
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "touch /home/$BOOTSTRAP_ADMIN_USERNAME/.azure/osServicePrincipal.json"
cat > /home/$BOOTSTRAP_ADMIN_USERNAME/.azure/osServicePrincipal.json <<EOF
{"subscriptionId":"$SUBSCRIPTION_ID","clientId":"$AAD_APPLICATION_ID","clientSecret":"$AAD_APPLICATION_SECRET","tenantId":"$TENANT_ID"}
EOF
echo $(date) " - Setup Azure Credentials for OCP - Complete" >> $DEBUG_LOG

# Create a directory in Bootstrap VM and clone the GitHub repository
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "mkdir -p $INSTALLER_HOME/experiments"
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "git clone --branch bash-ansible https://github.com/midhun6989/experiments.git $INSTALLER_HOME/experiments"

# Substitute the variables in install-config.yaml file
echo $(date) " - install-config.yaml Variables Substitution - Start" >> $DEBUG_LOG
sed -i "s/\$DNS_ZONE_NAME/$DNS_ZONE_NAME/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$COMPUTE_VM_SIZE/$COMPUTE_VM_SIZE/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$COMPUTE_DISK_SIZE/$COMPUTE_DISK_SIZE/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$COMPUTE_DISK_TYPE/$COMPUTE_DISK_TYPE/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$COMPUTE_INSTANCE_COUNT/$COMPUTE_INSTANCE_COUNT/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$CONTROL_PLANE_VM_SIZE/$CONTROL_PLANE_VM_SIZE/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$CONTROL_PLANE_DISK_SIZE/$CONTROL_PLANE_DISK_SIZE/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$CONTROL_PLANE_DISK_TYPE/$CONTROL_PLANE_DISK_TYPE/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$CONTROLPLANE_INSTANCE_COUNT/$CONTROLPLANE_INSTANCE_COUNT/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$CLUSTER_NAME/$CLUSTER_NAME/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed  "s|\$CLUSTER_NETWORK_CIDR|$CLUSTER_NETWORK_CIDR|g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml >> $INSTALLER_HOME/experiments/azure/scripts/install-config-new.yaml
rm $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
mv $INSTALLER_HOME/experiments/azure/scripts/install-config-new.yaml $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$HOST_ADDRESS_PREFIX/$HOST_ADDRESS_PREFIX/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed  "s|\$VIRTUAL_NETWORK_CIDR|$VIRTUAL_NETWORK_CIDR|g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml > $INSTALLER_HOME/experiments/azure/scripts/install-config-new.yaml
rm $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
mv $INSTALLER_HOME/experiments/azure/scripts/install-config-new.yaml $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed  "s|\$SERVICE_NETWORK_CIDR|$SERVICE_NETWORK_CIDR|g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml > $INSTALLER_HOME/experiments/azure/scripts/install-config-new.yaml
rm $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
mv $INSTALLER_HOME/experiments/azure/scripts/install-config-new.yaml $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$DNS_ZONE_RESOURCE_GROUP/$DNS_ZONE_RESOURCE_GROUP/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$LOCATION/$LOCATION/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$NETWORK_RESOURCE_GROUP/$NETWORK_RESOURCE_GROUP/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$VIRTUAL_NETWORK_NAME/$VIRTUAL_NETWORK_NAME/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$CONTROL_PLANE_SUBNET_NAME/$CONTROL_PLANE_SUBNET_NAME/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$COMPUTE_SUBNET_NAME/$COMPUTE_SUBNET_NAME/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$OUTBOUND_TYPE/$OUTBOUND_TYPE/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$CLUSTER_RESOURCE_GROUP_NAME/$CLUSTER_RESOURCE_GROUP_NAME/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$PULL_SECRET/$PULL_SECRET/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$ENABLE_FIPS/$ENABLE_FIPS/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$PRIVATE_OR_PUBLIC/$PRIVATE_OR_PUBLIC/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
sed -i "s/\$BOOTSTRAP_SSH_PUBLIC_KEY/$BOOTSTRAP_SSH_PUBLIC_KEY/g" $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
echo $(date) " - install-config.yaml Variables Substitution - Complete" >> $DEBUG_LOG

echo $(date) " - Setup Install Config - Start" >> $DEBUG_LOG
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "mkdir -p $INSTALLER_HOME/openshiftfourx"
if [[ $SINGLE_ZONE_OR_MULTI_ZONE != "az" ]]; then
  zones=`grep -A3 'zones' $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml`
  grep -v $zones $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml > $INSTALLER_HOME/experiments/azure/scripts/install-config-new.yaml
  rm $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml
  mv $INSTALLER_HOME/experiments/azure/scripts/install-config-new.yaml $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml    
fi  
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "cp $INSTALLER_HOME/experiments/azure/scripts/install-config.yaml $INSTALLER_HOME/openshiftfourx/install-config.yaml"
echo $(date) " - Setup Install Config - Complete" >> $DEBUG_LOG

echo $(date) " - OCP Install - Start" >> $DEBUG_LOG
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "export ARM_SKIP_PROVIDER_REGISTRATION=true"
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "$INSTALLER_HOME/openshift-install create cluster --dir=$INSTALLER_HOME/openshiftfourx --log-level=debug"
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "sleep 120"
echo $(date) " - OCP Install - Complete" >> $DEBUG_LOG

echo $(date) " - Setup Kube Config - Start" >> $DEBUG_LOG
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "mkdir -p /home/$BOOTSTRAP_ADMIN_USERNAME/.kube"
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "cp $INSTALLER_HOME/openshiftfourx/auth/kubeconfig /home/$BOOTSTRAP_ADMIN_USERNAME/.kube/config"
echo $(date) " - Setup Kube Config - Complete" >> $DEBUG_LOG

#Switch to Machine API project
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "oc project openshift-machine-api"

# Enable or Disable Autoscaler
if [[ $ENABLE_AUTOSCALER == "true" ]]; then
  clusterid=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.labels.machine\.openshift\.io/cluster-api-cluster}' --kubeconfig /home/$BOOTSTRAP_ADMIN_USERNAME/.kube/config)
  sed -i "s/\${clusterid}/$clusterid/g" $INSTALLER_HOME/experiments/azure/scripts/machine-autoscaler.yaml
  sed -i "s/\${LOCATION}/$LOCATION/g" $INSTALLER_HOME/experiments/azure/scripts/machine-autoscaler.yaml
  sed -i "s/\${clusterid}/$clusterid/g" $INSTALLER_HOME/experiments/azure/scripts/machine-health-check.yaml
  sed -i "s/\${LOCATION}/$LOCATION/g" $INSTALLER_HOME/experiments/azure/scripts/machine-health-check.yaml
  echo $(date) " - Setup Cluster Autoscaler - Start" >> $DEBUG_LOG
  runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "oc create -f $INSTALLER_HOME/experiments/azure/scripts/cluster-autoscaler.yaml"
  echo $(date) " - Setup Cluster Autoscaler - Complete" >> $DEBUG_LOG
  echo $(date) " - Setup Machine Autoscaler - Start" >> $DEBUG_LOG
  runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "oc create -f $INSTALLER_HOME/experiments/azure/scripts/machine-autoscaler.yaml"
  echo $(date) " - Setup Machine Autoscaler - Complete" >> $DEBUG_LOG
  echo $(date) " - Setup Machine Health Checks - Start" >> $DEBUG_LOG
  runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "oc create -f $INSTALLER_HOME/experiments/azure/scripts/machine-health-check.yaml"
  echo $(date) " - Setup Machine Health Checks - Complete" >> $DEBUG_LOG
fi

# Create a User for Login to OpenShift Console
echo $(date) " - Creating $OPENSHIFT_USERNAME User - Start" >> $DEBUG_LOG
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "htpasswd -c -B -b /tmp/.htpasswd '$OPENSHIFT_USERNAME' '$OPENSHIFT_PASSWORD'"
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "sleep 5"
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "oc create secret generic htpass-secret --from-file=htpasswd=/tmp/.htpasswd -n openshift-config"
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "oc apply -f $INSTALLER_HOME/experiments/azure/scripts/openshift-auth.yaml"
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "oc adm policy add-cluster-role-to-user cluster-admin '$OPENSHIFT_USERNAME'"
echo $(date) " - Creating $OPENSHIFT_USERNAME User - Complete" >> $DEBUG_LOG

echo $(date) " - Setup IBM Operator Catalog - Start" >> $DEBUG_LOG
runuser -l $BOOTSTRAP_ADMIN_USERNAME -c "oc apply -f $INSTALLER_HOME/experiments/azure/scripts/ibm-operator-catalog.yaml"
echo $(date) " - Setup IBM Operator Catalog - Complete" >> $DEBUG_LOG

echo $(date) " - ############### Deploy Script - Complete ###############" >> $DEBUG_LOG