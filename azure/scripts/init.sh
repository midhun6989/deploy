#!/bin/bash
set -ex

echo $(date) " - ############## Init Script ####################"

echo "Updating packages and installing package dependencies"
sudo dnf update -y

# Install git and clone git repository containing deployment scripts/artifacts
function cloneRepo() {
	sudo dnf install git -y

	echo "\nChecking git version"
	git --version

	echo "\nLoading zmodstack-deploy key"
	touch ~/.ssh/id_rsa
	cat > ~/.ssh/id_rsa <<- EOL
	-----BEGIN OPENSSH PRIVATE KEY-----
	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
	-----END OPENSSH PRIVATE KEY-----
	EOL
	chmod 400 ~/.ssh/id_rsa

	ssh-keyscan -t rsa github.ibm.com >> ~/.ssh/known_hosts
	git clone --branch dev git@github.ibm.com:IBM-Z-and-Cloud-Modernization-Stack/deploy.git /mnt/zmodstack-deploy
}

function initAzCLI() {
	echo "Installing Azure CLI"
	sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
	sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
	sudo dnf install -y azure-cli jq

	echo "Setup Azure CLI"
	az login --identity
}

function deployOCP() {
	exec /mnt/zmodstack-deploy/azure/scripts/deployOpenshift.sh
}


cloneRepo
initAzCLI
deployOCP