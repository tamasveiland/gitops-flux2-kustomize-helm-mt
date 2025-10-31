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

# Update
az k8s-configuration flux update -g $MY_RESOURCE_GROUP_NAME `
-c $MY_AKS_CLUSTER_NAME `
-n cluster-config `
-t managedClusters `
-u https://github.com/tamasveiland/gitops-flux2-kustomize-helm-mt `
--branch main  `
--kustomization name=infra path=./infrastructure prune=true force=true `
--kustomization name=apps path=./apps/staging prune=true force=true dependsOn=infra


kubectl get fluxconfigs -A
kubectl get gitrepositories -A
kubectl get helmreleases -A
kubectl get kustomizations -A

# Configure log level
az k8s-extension update --resource-group $MY_RESOURCE_GROUP_NAME `
                        --cluster-name $MY_AKS_CLUSTER_NAME `
                        --cluster-type managedClusters `
                        --name flux `
                        --config source-controller.log-level=error kustomize-controller.log-level=error

# Enforce reconciliation
az k8s-configuration flux reconcile kustomization infra --with-source --force

flux get kustomizations
flux get helmreleases
flux reconcile kustomization <name> --with-source
flux reconcile helmrelease <name> --namespace <namespace>
flux reconcile kustomization cluster-config-infra --with-source --force --namespace cluster-config
