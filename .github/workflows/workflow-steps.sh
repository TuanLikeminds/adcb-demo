#!/bin/bash

AZURE_IDENTITY=$AZURE_IDENTITY
AZURE_SUBSCRIPTION=$AZURE_SUBSCRIPTION
AZURE_AKS_CLUSTER_NAME=$AZURE_AKS_CLUSTER_NAME
AZURE_AKS_CLUSTER_RESOURCE_GROUP=$AZURE_AKS_CLUSTER_RESOURCE_GROUP
PRODUCT_NAME=$PRODUCT_NAME
ACR_REGISTRY_URL=$ACR_REGISTRY_URL
RELEASE_TAG=$RELEASE_TAG
ACR_REGISTRY_NAME=$ACR_REGISTRY_NAME
BASE_IMAGE_TAG=$BASE_IMAGE_TAG
BASE_IMAGE_REPOSITORY=$BASE_IMAGE_REPOSITORY
PRODUCT_NAME=$PRODUCT_NAME
ACR_REGISTRY_URL=$ACR_REGISTRY_URL

apply_overlays() {
  echo "Applying overlays..."

  echo "Azure login"
  export APPSETTING_WEBSITE_SITE_NAME='azcli-workaround'
  az login --identity --username $AZURE_IDENTITY
  az account set --subscription $AZURE_SUBSCRIPTION

  echo "Azure AKS credentials"
  az aks get-credentials --name $AZURE_AKS_CLUSTER_NAME --resource-group $AZURE_AKS_CLUSTER_RESOURCE_GROUP

  echo "AKS apply"
  kubelogin convert-kubeconfig -l azurecli
  # @TODO: Remove yq lines after aks-54uma725.privatelink.uaenorth.azmk8s.io gets added to InfoBlox
  yq e -i '.clusters[].cluster.server = "https://aks-pbky1iij.hcp.uaenorth.azmk8s.io:443"' ~/.kube/config
  yq e -i '.clusters[].cluster.certificate-authority-data = null' ~/.kube/config
  yq e -i '.clusters[].cluster.insecure-skip-tls-verify = true' ~/.kube/config
  #kubectl create secret generic pingdirectory-license --from-file=k8s/base/ciam/ping-directory/PingDirectory.lic -n ciam-dev
  #curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  #kubectl create secret tls ping-fed-secret --cert=helm/ping-federate/ping-fed.crt --key=helm/ping-federate/ping-fed.key -n ciam-dev
  #kubectl create secret generic pingauthorize.lic --from-file=k8s/base/ciam/ping-authorize/PingAuthorize.lic -n ciam-dev
  #kubectl create secret tls ping-secret --cert=helm/ping-federate/ping-all.crt --key=helm/ping-federate/ping-all.key -n ciam-dev
  kubectl create secret generic pingauthorize.lic --from-file=k8s/base/ciam/ping-authorize/PingAuthorize.lic -n ciam-dev
  kubectl create secret tls ping-secret --cert=helm/ping-federate/ping-all.crt --key=helm/ping-federate/ping-all.key -n ciam-dev
  #kubectl create secret tls ping-fedadmin-secret --cert=helm/ping-federate/ping-fedadmin.crt --key=helm/ping-federate/ping-fedadmin.key -n ciam-dev
  #kubectl create secret tls ping-fedeng-secret --cert=helm/ping-federate/ping-fedeng.crt --key=helm/ping-federate/ping-fedeng.key -n ciam-dev
  #kubectl create secret tls ping-auth-secret --cert=helm/ping-authorize/ping-auth.crt --key=helm/ping-authorize/ping-auth.key -n ciam-dev
  #kubectl apply -f helm/nginx-ingress/deployment.yaml -n ciam-dev
  #kubectl apply -f helm/ping-data-console/ping-dataconsole-ingress.yaml -n ciam-dev
  kubectl delete cm global-env-vars -n ciam-dev 
  helm upgrade --install  pingauthorize-release  ping-devops --version 0.10.0 --repo https://helm.pingidentity.com -f helm/ping-authorize/ping-authorize-values.yaml --namespace ciam-dev  --force    
  kubectl apply -f helm/ping-directory/service.yaml -n ciam-dev
  # @TODO: automate the environment name - see cibg-infra repo
  #kubectl delete svc ping-directory-lb-svc -n ciam-dev
  #kustomize build k8s/overlays/dev | kubectl apply -f -
  kubectl apply -f helm/ping-authorize/ingress-pingauthorize.yaml -n ciam-dev
  kubectl apply -f helm/ping-federate/ingress-pingfederate-admin.yaml -n ciam-dev
  kubectl apply -f helm/ping-federate/ingress-pingfederate-engine.yaml -n ciam-dev
  kubectl apply -f helm/ping-directory/ingress-pingdirectory.yaml -n ciam-dev
  #kubectl create secret generic pingfederate.lic --from-file=k8s/base/ciam/ping-federate/pingfederate.lic -n ciam-dev
  kubectl delete cm global-env-vars -n ciam-dev
  helm upgrade --install  pingdirectory-release  ping-devops --version 0.10.0 --repo https://helm.pingidentity.com -f helm/ping-directory/pingdirectory-values.yaml --namespace ciam-dev  --force 
  kubectl delete cm global-env-vars -n ciam-dev
  helm upgrade --install  pingfederate-release  ping-devops --version 0.10.0 --repo https://helm.pingidentity.com -f helm/ping-federate/pingfederate-values.yaml --namespace ciam-dev --force 
  kubectl delete cm global-env-vars -n ciam-dev
  helm upgrade --install  pingdataconsole-release  ping-devops --version 0.10.0 --repo https://helm.pingidentity.com -f helm/ping-data-console/pingdataconsole-values.yaml --namespace ciam-dev --force 
  kubectl get deploy -o wide -n ciam-dev
  kubectl get pods -n ciam-dev
}

build_pingdirectory_image() {

  echo "Azure login"
  az login --service-principal -u "6fca71cf-2e16-48fd-9c52-cb1d0f72b898" -p "r6U8Q~JYsjXxkjeILYVegugmEtBgxwv9sBxCXbDO" --tenant "daecf046-26ba-44b7-bdd6-032e51085396"
  echo "Building $PRODUCT_NAME Image: $RELEASE_TAG"
  echo "Deploying $PRODUCT_NAME - DEV"
  echo "Logging into ACR"
  az acr login --name pingdevops
  
  #STEP 1 - CHECK IF THE BASE IMAGE EXISTS IN THE BASE IMAGE REPOSITORY
  echo "Check if $PRODUCT_NAME Base image $BASE_IMAGE_TAG exists"
  echo 
  # Check if the base image exists in the Azure Container Registry (ACR)
  if ! az acr repository show-tags --name $ACR_REGISTRY_NAME --repository $BASE_IMAGE_REPOSITORY --output tsv | grep -q "$BASE_IMAGE_TAG"; then
  #Scripts throws and exception and exits If the base image tag does not exist in ACR
    echo "Error: Base image $BASE_IMAGE_REPOSITORY:$BASE_IMAGE_TAG does not exist in the ACR repository.... Exiting The Deployment Pipeline..."
    echo "Push $BASE_IMAGE_REPOSITORY:$BASE_IMAGE_TAG to the $ACR_REGISTRY_NAME Registry to continue..."
    
    exit 1
  fi

  echo "Base image tag $BASE_IMAGE_TAG found. $PRODUCT_NAME Image $RELEASE_TAG will be built using this image..."



  #STEP 2 - IF THE BASE IMAGE EXISTS, THEN INJECT THE SERVER PROFILE INTO THE IMAGE AND PUSH IT TO ACR
  echo "building $PRODUCT_NAME image and pushing it to ACR"

  if ! az acr build \
  --registry $ACR_REGISTRY_NAME \
  --image $PRODUCT_NAME:$RELEASE_TAG \
  --build-arg ACR_REGISTRY_URL=$ACR_REGISTRY_URL \
  --build-arg BASE_IMAGE_TAG=$BASE_IMAGE_TAG \
  --build-arg BASE_IMAGE_REPOSITORY=$BASE_IMAGE_REPOSITORY \
  -f $PRODUCT_NAME/Dockerfile $PRODUCT_NAME/; then
  
  # If the build fails, throw an error and exit the script
  echo "Error: Failed to build $PRODUCT_NAME image and push it to ACR... Exiting the Deployment Pipeline..."
  exit 1
  fi

echo "$PRODUCT_NAME image successfully built and pushed to ACR."








}

action=${1//-/_}
$action ${@:2}
