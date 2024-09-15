#!/bin/bash

AZURE_IDENTITY=$AZURE_IDENTITY
AZURE_SUBSCRIPTION=$AZURE_SUBSCRIPTION
AZURE_AKS_CLUSTER_NAME=$AZURE_AKS_CLUSTER_NAME
AZURE_AKS_CLUSTER_RESOURCE_GROUP=$AZURE_AKS_CLUSTER_RESOURCE_GROUP


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

action=${1//-/_}
$action ${@:2}
