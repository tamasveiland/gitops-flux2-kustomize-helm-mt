$RANDOM_ID="$(openssl rand -hex 3)"
$MY_RESOURCE_GROUP_NAME="rg-aks-store-demo"
$IDENTITY_NAME="id-aks-store-demo"
$REGION="swedencentral"
$MY_AKS_CLUSTER_NAME="aks-store-demo01"
$MY_DNS_LABEL="mydnslabel$RANDOM_ID"
$VNET_NAME="vnet-aks-store-demo"
$SUBNET_NAME="snet-aks-store-demo"
$NEW_SUBNET_NAME="snet-aks-workloads"
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

# Create additional subnet for workloads
az network vnet subnet create `
  --resource-group $MY_RESOURCE_GROUP_NAME `
  --vnet-name $VNET_NAME `
  --name $NEW_SUBNET_NAME `
  --address-prefix 10.0.241.0/24

$SUBNET_ID=$(az network vnet subnet show --resource-group $MY_RESOURCE_GROUP_NAME --vnet-name $VNET_NAME --name $SUBNET_NAME --query "id" -o tsv)
$NEW_SUBNET_ID=$(az network vnet subnet show --resource-group $MY_RESOURCE_GROUP_NAME --vnet-name $VNET_NAME --name $NEW_SUBNET_NAME --query "id" -o tsv)

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

# az aks create `
#   --resource-group $MY_RESOURCE_GROUP_NAME `
#   --name $MY_AKS_CLUSTER_NAME `
#   --enable-managed-identity `
#   --assign-identity $IDENTITY_ID `
#   --network-plugin azure `
#   --network-plugin-mode overlay `
#   --vnet-subnet-id $SUBNET_ID `
#   --enable-aad `
#   --aad-admin-group-object-ids $AKS_ADMINS_GROUP_ID `
#   --aad-tenant-id $TENANT_ID `
#   --enable-azure-rbac `
#   --attach-acr $ACR_NAME `
#   --node-count 3 `
#   --service-cidr 172.16.0.0/16 `
#   --dns-service-ip 172.16.0.10 `
#   --pod-cidr 172.17.0.0/16 `
#   --generate-ssh-keys `
#   --enable-oidc-issuer `
#   --enable-workload-identity

az aks create `
  --resource-group $MY_RESOURCE_GROUP_NAME `
  --name aks-demo01 `
  --enable-managed-identity `
  --assign-identity $IDENTITY_ID `
  --network-plugin azure `
  --network-plugin-mode overlay `
  --vnet-subnet-id $NEW_SUBNET_ID `
  --enable-aad `
  --aad-admin-group-object-ids $AKS_ADMINS_GROUP_ID `
  --aad-tenant-id $TENANT_ID `
  --enable-azure-rbac `
  --attach-acr $ACR_NAME `
  --node-count 3 `
  --service-cidr 172.16.0.0/16 `
  --dns-service-ip 172.16.0.10 `
  --pod-cidr 172.17.0.0/16 `
  --generate-ssh-keys `
  --enable-oidc-issuer `
  --enable-workload-identity


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


# Enable OIDC and Workload Identity
az aks update -g $MY_RESOURCE_GROUP_NAME -n $MY_AKS_CLUSTER_NAME --enable-oidc-issuer --enable-workload-identity

# Get ACR resource ID and grant AcrPull role to the managed identity
$ACR_ID=$(az acr show --name $ACR_NAME --resource-group $MY_RESOURCE_GROUP_NAME --query "id" -o tsv)
$IDENTITY_PRINCIPAL_ID=$(az identity show --name $IDENTITY_NAME --resource-group $MY_RESOURCE_GROUP_NAME --query "principalId" -o tsv)
az role assignment create --assignee $IDENTITY_PRINCIPAL_ID --role AcrPull --scope $ACR_ID

# Create federated credential for Flux source controller
$AKS_OIDC_ISSUER = az aks show -g $MY_RESOURCE_GROUP_NAME -n $MY_AKS_CLUSTER_NAME --query "oidcIssuerProfile.issuerUrl" -o tsv
az identity federated-credential create --name "flux-source-controller" --identity-name $IDENTITY_NAME --resource-group $MY_RESOURCE_GROUP_NAME --issuer $AKS_OIDC_ISSUER --subject "system:serviceaccount:flux-system:source-controller" --audience "api://AzureADTokenExchange"
$IDENTITY_CLIENT_ID = az identity show -g $MY_RESOURCE_GROUP_NAME -n $IDENTITY_NAME --query "clientId" -o tsv
# annotate the Flux source controller service account with the client ID of the managed identity
kubectl annotate serviceaccount -n flux-system source-controller azure.workload.identity/client-id="$IDENTITY_CLIENT_ID"
kubectl label serviceaccount -n flux-system source-controller azure.workload.identity/use=true
# restart the source controller deployment so it picks up the new workload identity configuration
kubectl rollout restart deployment/source-controller -n flux-system
kubectl rollout status deployment/source-controller -n flux-system

kubectl get ocirepository acr-oci -n cluster-config
az acr repository list --name "acrakstoredemo23c3e0" --output table
# try to trigger a reconciliation of the OCIRepository
kubectl patch ocirepository acr-oci -n cluster-config --type merge -p '{"spec":{"interval":"10s"}}'

kubectl create secret docker-registry acr-secret --namespace cluster-config --docker-server="$ACR_NAME.azurecr.io" --docker-username="$SP_APP_ID" --docker-password="$SP_PASSWD"
az ad sp create-for-rbac --name $SERVICE_PRINCIPAL_NAME --scopes $ACR_REGISTRY_ID --role acrpull --query "password" --output tsv



az aks get-credentials --resource-group $MY_RESOURCE_GROUP_NAME --name $MY_AKS_CLUSTER_NAME

kubectl get nodes

