## Ansible Playbook

### Provision of OCP Cluster using Ansible Playbook

1. Install the dependencies.
   ```
   pip install 'ansible[azure]'
   ansible-galaxy collection install azure.azcollection
   pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements-azure.txt
   ```
2. Login to Azure using CLI. 
   ```
   az login
   ```
3. Create a Key Vault. Add the secrets to Key Vault.
   ```
   az keyvault create --name z-mod-stack-kv --resource-group z-mod-stack-rg --location EastUS
   ```
    1. **aadClientSecret** ---> Password for the Service Principal 
    1. **apiKey** ---> Same as Entitlement API Key 
    1. **openshiftPassword** ---> Set a password for login to OpenShift UI 
    1. **pullSecret** ---> Pull Secret obtained from Red Hat 
    1. **sshPublicKey** ---> Public Key of the RSA key pair generated 
    <img width="1171" alt="Screenshot 2023-04-17 at 10 57 27 AM" src="https://media.github.ibm.com/user/401002/files/71161c58-b92b-4979-bc77-935d67a6e9cb">
4. Clone the GitHub repository https://github.ibm.com/IBM-Z-and-Cloud-Modernization-Stack/azure.git to local system.
5. Change directory to `ansible`.
   ```
   cd ansible
   ```
6. Substitute the Ansible variables in `run-provision.yml` with appropriate values. 
   https://github.ibm.com/IBM-Z-and-Cloud-Modernization-Stack/azure/blob/dev/ansible/run-provision.yml#L8-L21 
    1. **RESOURCE_GROUP** ---> Name of the Resource Group for Key Vault 
    2. **SCRIPTS_CONTAINER** ---> Name of the Container 
    3. **SCRIPTS_BLOB** ---> Name of the Blob 
    4. **SCRIPT_SOURCE** ---> Source of the `deployOpenShift.sh` 
    5. **KEY_VAULT** ---> Name of the Key Vault 
    6. **TENANT_ID** ---> Azure Tenant Id 
    7. **USER_OBJECT_ID** ---> Object Id of the User in Azure Active Directory 
    8. **APP_OBJECT_ID** ---> Object Id of the Application in Azure Active Directory 
    9. **CLUSTER_RESOURCE_GROUP** ---> Name of the Resource Group for Controlplane and Compute resources 
    10. **DEPLOYMENT_NAME** ---> Name of the Deployment 
    11. **BOOTSTRAP_RESOURCE_GROUP** ---> Name of the Resource Group for Bootstrap and Virtual Network resources 
    12. **OCP_TEMPLATE** ---> Path of the ARM Template file in local system 
    13. **OCP_PARAMS** ---> Path of the ARM Parameters file in local system
7. Execute the Ansible playbook for provisioning.
   ```
   ansible-playbook run-provision.yml --extra-vars LOCATION=eastus
   ```
    
### Deprovision of OCP Cluster using Ansible Playbook    

1. Install the dependencies.
   ```
   pip install 'ansible[azure]'
   ansible-galaxy collection install azure.azcollection
   pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements-azure.txt
   ```
2. Login to Azure using CLI. 
   ```
   az login
   ```
3. Clone the GitHub repository https://github.ibm.com/IBM-Z-and-Cloud-Modernization-Stack/azure.git to local system.
4. Change directory to `ansible`.
   ```
   cd ansible
   ```
5. Substitute the Ansible variables in `run-deprovision.yml` with appropriate values. 
   https://github.ibm.com/IBM-Z-and-Cloud-Modernization-Stack/azure/blob/dev/ansible/run-deprovision.yml#L8-L9  
    1. **CLUSTER_RESOURCE_GROUP** ---> Name of the Resource Group for Controlplane and Compute resources 
    1. **BOOTSTRAP_RESOURCE_GROUP** ---> Name of the Resource Group for Bootstrap and Virtual Network resources 
6. Execute the Ansible playbook for deprovisioning.
   ```
   ansible-playbook run-deprovision.yml
   ```
   