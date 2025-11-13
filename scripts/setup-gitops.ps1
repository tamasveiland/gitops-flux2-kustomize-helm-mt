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
# flux reconcile kustomization <name> --with-source
# flux reconcile helmrelease <name> --namespace <namespace>
flux reconcile kustomization cluster-config-infra --with-source --force --namespace cluster-config
flux reconcile helmrelease redis --namespace cluster-config

# configure the workload identity for the Flux source controller. Let me apply the missing annotations and labels
kubectl annotate serviceaccount -n flux-system source-controller azure.workload.identity/client-id="$IDENTITY_CLIENT_ID" --overwrite
kubectl label serviceaccount -n flux-system source-controller azure.workload.identity/use=true --overwrite
# Check federated credential
az identity federated-credential list --identity-name $IDENTITY_NAME --resource-group $MY_RESOURCE_GROUP_NAME --query "[?name=='flux-source-controller']"

kubectl rollout restart deployment/source-controller -n flux-system
kubectl rollout status deployment/source-controller -n flux-system

# force a reconciliation of the HelmRepository
kubectl annotate gitrepository cluster-config -n cluster-config --overwrite reconcile.fluxcd.io/requestedAt="$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"

# force a reconciliation of the Kustomization
kubectl patch kustomization cluster-config-infra -n cluster-config --type merge -p '{"spec":{"force":true}}'

kubectl patch kustomization cluster-config-infra -n cluster-config --type merge -p '{"spec":{"force":true,"interval":"10s"}}'

# Clean up old ACR secret (no longer needed with workload identity)
kubectl delete secret acr-secret -n cluster-config --ignore-not-found=true

# Force reconciliation of the HelmRepository to use workload identity
kubectl annotate helmrepository acr-oci -n cluster-config --overwrite reconcile.fluxcd.io/requestedAt="$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
kubectl get helmrelease redis -n cluster-config

# Verify workload identity configuration
kubectl describe serviceaccount source-controller -n flux-system
kubectl get helmrepository acr-oci -n cluster-config -o yaml

kubectl logs -n flux-system -l app=source-controller --tail=20

kubectl annotate serviceaccount -n flux-system source-controller azure.workload.identity/client-id="$IDENTITY_CLIENT_ID" --overwrite

# Add label to the flux-system namespace to enable workload identity
kubectl label namespace flux-system azure.workload.identity/use=true

kubectl exec -n default -it workload-identity-test -c oidc -- /bin/bash

###################################
# Get the login server of the ACR #
###################################
$ACR_LOGIN_SERVER=$(az acr show -n $ACR_NAME -g $MY_RESOURCE_GROUP_NAME --query "loginServer" -o tsv)
# namespace used by your HelmRepository in attachment is cluster-config
$ns = "cluster-config"
$secretName = "acr-credentials"
$clientId = "ed20f3b1-51d6-47f8-840d-c609ab4c8c71"
$clientSecret = "kdc8Q~lzKOrEwog-JE6f-K.keqwdW-SuTI0hybFZ"

kubectl create secret docker-registry $secretName `
  --docker-server=$ACR_LOGIN_SERVER `
  --docker-username=$clientId `
  --docker-password=$clientSecret `
  -n $ns




###################################
# Test ingress #
###################################
kubectl run test-pod --rm -i --tty --restart=Never --image=curlimages/curl -- curl -v http://podinfo.podinfo:9898/

kubectl run test-ingress --rm -i --tty --restart=Never --image=curlimages/curl -- curl -v -H "Host: podinfo.staging" http://135.116.251.205/

kubectl port-forward -n podinfo svc/podinfo 8080:9898
