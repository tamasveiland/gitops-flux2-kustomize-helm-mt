

# Login to ACR
az acr login --name acrakstoredemo23c3e0.azurecr.io

# helm dependency update ./redis to download the missing common chart
# Created charts directory: This populated the charts/ directory with common-2.31.4.tgz

# Package helm chart
helm package ./redis

# Push helm chart to ACR
# helm push redis-*.tgz oci://<your-acr-name>.azurecr.io
helm push redis-23.0.5.tgz oci://acrakstoredemo23c3e0.azurecr.io/helm