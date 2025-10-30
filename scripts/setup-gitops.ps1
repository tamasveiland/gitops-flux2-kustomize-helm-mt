# https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/tutorial-use-gitops-flux2?tabs=azure-cli


$RANDOM_ID="$(openssl rand -hex 3)"
$MY_RESOURCE_GROUP_NAME="rg-aks-store-demo"
$IDENTITY_NAME="id-aks-store-demo"
$REGION="swedencentral"
$MY_AKS_CLUSTER_NAME="aks-store-demo01"
$MY_DNS_LABEL="mydnslabel$RANDOM_ID"
$VNET_NAME="vnet-aks-store-demo"
$SUBNET_NAME="snet-aks-store-demo"
$AKS_ADMINS_GROUP_NAME="AKS-Admins"
$ACR_NAME="acrakstoredemo$RANDOM_ID"
$TENANT_ID=$(az account show --query "tenantId" -o tsv)


az extension add -n k8s-configuration
az extension add -n k8s-extension

az extension update -n k8s-configuration
az extension update -n k8s-extension

az extension list -o table


az k8s-configuration flux create -g $MY_RESOURCE_GROUP_NAME `
-c $MY_AKS_CLUSTER_NAME `
-n cluster-config `
--namespace cluster-config `
-t managedClusters `
--scope cluster `
-u https://github.com/tamasveiland/gitops-flux2-kustomize-helm-mt `
--branch main  `
--kustomization name=infra path=./infrastructure prune=true `
--kustomization name=apps path=./apps/staging prune=true dependsOn=infra

