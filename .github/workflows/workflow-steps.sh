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
WORKLOAD_TYPE=$WORKLOAD_TYPE
NAMESPACE=$NAMESPACE

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
  # helm upgrade --install  pingdirectory-release  ping-devops --version 0.10.0 --repo https://helm.pingidentity.com -f helm/ping-directory/pingdirectory-values.yaml --namespace ciam-dev  --force 
  kubectl delete cm global-env-vars -n ciam-dev
  helm upgrade --install  pingfederate-release  ping-devops --version 0.10.0 --repo https://helm.pingidentity.com -f helm/ping-federate/pingfederate-values.yaml --namespace ciam-dev --force 
  kubectl delete cm global-env-vars -n ciam-dev
  helm upgrade --install  pingdataconsole-release  ping-devops --version 0.10.0 --repo https://helm.pingidentity.com -f helm/ping-data-console/pingdataconsole-values.yaml --namespace ciam-dev --force 
  kubectl get deploy -o wide -n ciam-dev
  kubectl get pods -n ciam-dev
}
#-------------------------#-------------------------#-------------------------
########## build_ping_image FUNCTION TO BUILD AND PUSH PING IMAGE TO ACR ##########
#-------------------------#-------------------------#-------------------------

  #1. Authenticate against ACR
  #2. Check if base image exists
  #3. Build ping docker image and push to ACR

build_ping_image() {
  #STEP 1 - Authenticate to aks and acr
  echo "Azure login"
  export APPSETTING_WEBSITE_SITE_NAME='azcli-workaround'
  az login --identity --username $AZURE_IDENTITY
  az account set --subscription $AZURE_SUBSCRIPTION

  echo "Building $PRODUCT_NAME Image: $RELEASE_TAG"
  echo "Logging into ACR"
  az acr login --name $ACR_REGISTRY_NAME

  #-------------------------
  
  #STEP 2 - CHECK IF THE BASE IMAGE EXISTS IN THE BASE IMAGE REPOSITORY
  echo "Check if $PRODUCT_NAME Base image $BASE_IMAGE_TAG exists"
  echo 
  
  if ! az acr repository show-tags --name $ACR_REGISTRY_NAME --repository $BASE_IMAGE_REPOSITORY --output tsv | grep -q "$BASE_IMAGE_TAG"; then
  #Scripts throws and exception and exits If the base image tag does not exist in ACR
    echo "Error: Base image $BASE_IMAGE_REPOSITORY:$BASE_IMAGE_TAG does not exist in the ACR repository.... Exiting The Deployment Pipeline..."
    echo "Push $BASE_IMAGE_REPOSITORY:$BASE_IMAGE_TAG to the $ACR_REGISTRY_NAME Registry to continue..."
    
    exit 1
  fi

  echo "Base image tag $BASE_IMAGE_TAG found. $PRODUCT_NAME Image $RELEASE_TAG will be built using this image..."

  #-------------------------

  #STEP 3 - IF THE BASE IMAGE EXISTS, THEN BUILD THE IMAGE WITH INJECTED SERVER PROFILE AND PUSH IT TO ACR
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

  #-------------------------#-------------------------#-------------------------
  ######## deploy_pingdirectory FUNCTION TO INSTALL HELM CHART IN AKS ##########
  #-------------------------#-------------------------#-------------------------
  
  #1. Install helm CLI
  #2. Connect Obtain AKS credentials and set kubeconfig context
  #3. Delete exisintg global-env-vars configmap
  #5. Install the helm Release


deploy_pingdirectory(){
  # STEP 1 - INSTALL HELM CLI
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  # STEP 2 - CONNECT TO THE CLUSTER
  echo "Setting Azure AKS credentials"
  az aks get-credentials --name $AZURE_AKS_CLUSTER_NAME --resource-group $AZURE_AKS_CLUSTER_RESOURCE_GROUP
  # STEP 3 - SET KUBECONFIG
  echo "Configuring Kubectl"
  kubelogin convert-kubeconfig -l azurecli
  # @TODO: Remove yq lines after aks-54uma725.privatelink.uaenorth.azmk8s.io gets added to InfoBlox
  yq e -i '.clusters[].cluster.server = "https://aks-pbky1iij.hcp.uaenorth.azmk8s.io:443"' ~/.kube/config
  yq e -i '.clusters[].cluster.certificate-authority-data = null' ~/.kube/config
  yq e -i '.clusters[].cluster.insecure-skip-tls-verify = true' ~/.kube/config

  # STEP 4 - Delete exisintg global-env-vars configmap
  kubectl delete cm global-env-vars -n $NAMESPACE
  # STEP 3 - INSTALL HELM RELEASE
  helm upgrade --install  pingdirectory-release  ping-devops --version 0.10.0 --repo https://helm.pingidentity.com -f pingdirectory/helm/dev/values.yaml --namespace $NAMESPACE  --set pingdirectory.image.tag=$RELEASE_TAG  --force 
  kubectl get pods -n $NAMESPACE
  kubectl describe sts pingdirectory -n $NAMESPACE
}

deploy_pingfederate(){
  # STEP 1 - INSTALL HELM CLI
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  # STEP 2 - CONNECT TO THE CLUSTER
  echo "Setting Azure AKS credentials"
  az aks get-credentials --name $AZURE_AKS_CLUSTER_NAME --resource-group $AZURE_AKS_CLUSTER_RESOURCE_GROUP
  # STEP 3 - SET KUBECONFIG
  echo "Configuring Kubectl"
  kubelogin convert-kubeconfig -l azurecli
  # @TODO: Remove yq lines after aks-54uma725.privatelink.uaenorth.azmk8s.io gets added to InfoBlox
  yq e -i '.clusters[].cluster.server = "https://aks-pbky1iij.hcp.uaenorth.azmk8s.io:443"' ~/.kube/config
  yq e -i '.clusters[].cluster.certificate-authority-data = null' ~/.kube/config
  yq e -i '.clusters[].cluster.insecure-skip-tls-verify = true' ~/.kube/config

  # STEP 4 - Delete exisintg global-env-vars configmap
  kubectl delete cm global-env-vars -n $NAMESPACE
  # STEP 3 - INSTALL HELM RELEASE
  helm upgrade --install  pingfederate-release  ping-devops  --version 0.10.0 --repo https://helm.pingidentity.com -f pingfederate/helm/dev/values.yaml --namespace $NAMESPACE  --set pingfederate-admin.image.tag=$RELEASE_TAG --set pingfederate-engine.image.tag=$RELEASE_TAG  --force 
  kubectl get pods -n $NAMESPACE
  kubectl describe sts pingdirectory -n $NAMESPACE
}

# deploy_pingdirectory_staging(){
#   # TODO
# }


#-------------------------#-------------------------#-------------------------
########## Healthcheck for workloads ##########
#-------------------------#-------------------------#-------------------------

post_deployment_healthcheck(){
REPLICAS=$(kubectl get $WORKLOAD_TYPE $PRODUCT_NAME -n $NAMESPACE -o jsonpath='{.spec.replicas}')

# Function to check if all replicas are running
check_replicas_running() {
  READY_REPLICAS=$(kubectl get $WORKLOAD_TYPE "$PRODUCT_NAME" -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
  if [[ "$READY_REPLICAS" == "$REPLICAS" ]]; then
    return 0  # All replicas are running
  else
    return 1  # Not all replicas are running
  fi
}

# Retry loop to wait for StatefulSet or Deployment to be fully up and running
MAX_RETRIES=60
SLEEP_TIME=15

for (( i=0; i<MAX_RETRIES; i++ )); do
  if check_replicas_running; then
    echo "All $READY_REPLICAS replicas of $WORKLOAD_TYPE '$PRODUCT_NAME' are running."
    # Send notification to admin (replace with your notification system)
    # Example: echo "All replicas are running. Notify admin here."
    exit 0
  else
    echo "Waiting for all replicas to be ready... ($READY_REPLICAS/$REPLICAS)"
  fi
  sleep $SLEEP_TIME
done

echo "Timed out waiting for all replicas to be ready."
# Send failure notification (replace with your notification system)
# Example: echo "Replicas not ready. Notify admin here."
exit 1

}



action=${1//-/_}
$action ${@:2}
