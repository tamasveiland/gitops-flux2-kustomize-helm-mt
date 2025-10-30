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

az group create --name $MY_RESOURCE_GROUP_NAME --location $REGION

az network vnet create `
  --resource-group $MY_RESOURCE_GROUP_NAME `
  --name $VNET_NAME `
  --address-prefix 10.0.0.0/16 `
  --subnet-name $SUBNET_NAME `
  --subnet-prefix 10.0.240.0/24

$SUBNET_ID=$(az network vnet subnet show --resource-group $MY_RESOURCE_GROUP_NAME --vnet-name $VNET_NAME --name $SUBNET_NAME --query "id" -o tsv)

az identity create --name $IDENTITY_NAME --resource-group $MY_RESOURCE_GROUP_NAME
$IDENTITY_ID=$(az identity show --name $IDENTITY_NAME --resource-group $MY_RESOURCE_GROUP_NAME --query "id" -o tsv)

az acr create `
  --resource-group $MY_RESOURCE_GROUP_NAME `
  --name $ACR_NAME `
  --sku Standard `
  --location $REGION


# The UAMI needs Contributor or Network Contributor role on the resource group or VNet:
az role assignment create `
  --assignee $(az identity show --name $IDENTITY_NAME --resource-group $MY_RESOURCE_GROUP_NAME --query "principalId" -o tsv) `
  --role Contributor `
  --scope $(az group show --name $MY_RESOURCE_GROUP_NAME --query "id" -o tsv)

# Get Object ID of the AKS admin group
$AKS_ADMINS_GROUP_ID=$(az ad group show --group $AKS_ADMINS_GROUP_NAME --query objectId -o tsv)

az aks create --resource-group $MY_RESOURCE_GROUP_NAME --name $MY_AKS_CLUSTER_NAME --node-count 1 --generate-ssh-keys

az aks create `
  --resource-group $MY_RESOURCE_GROUP_NAME `
  --name $MY_AKS_CLUSTER_NAME `
  --enable-managed-identity `
  --assign-identity $IDENTITY_ID `
  --network-plugin azure `
  --network-plugin-mode overlay `
  --vnet-subnet-id $SUBNET_ID `
  --enable-aad `
  --aad-admin-group-object-ids $AKS_ADMINS_GROUP_ID `
  --aad-tenant-id $TENANT_ID `
  --enable-azure-rbac `
  --attach-acr $ACR_NAME `
  --node-count 3 `
  --service-cidr 172.16.0.0/16 `
  --dns-service-ip 172.16.0.10 `
  --pod-cidr 172.17.0.0/16 `
  --generate-ssh-keys


az aks update `
  --resource-group $MY_RESOURCE_GROUP_NAME `
  --name $MY_AKS_CLUSTER_NAME `
  --attach-acr $ACR_NAME


# # Get the ACR resource ID
# $ACR_ID=$(az acr show --name $ACR_NAME --resource-group $MY_RESOURCE_GROUP_NAME --query "id" -o tsv)
# # Grant AKS Managed Identity Access to ACR
# az role assignment create `
#   --assignee $(az aks show --resource-group $MY_RESOURCE_GROUP_NAME --name $MY_AKS_CLUSTER_NAME --query "identityProfile.kubeletidentity.objectId" -o tsv) `
#   --role AcrPull `
#   --scope $ACR_ID


az aks get-credentials --resource-group $MY_RESOURCE_GROUP_NAME --name $MY_AKS_CLUSTER_NAME

kubectl get nodes

