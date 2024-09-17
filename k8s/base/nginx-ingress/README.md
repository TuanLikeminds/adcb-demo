## 1. Download official manifests
```
mkdir -p k8s/base/nginx-ingress/vendor
helm template nginx-ingress oci://ghcr.io/nginxinc/charts/nginx-ingress \
    --version 1.3.1 \
    --namespace nginx-ingress \
    --set controller.enableCustomResources=false \
    --set controller.ingressClass.name=nginx-ingress \
    > k8s/base/nginx-ingress/vendor/nginx-ingress.yaml
```

[Helm Configuration Options](https://docs.nginx.com/nginx-ingress-controller/installation/installing-nic/installation-with-helm/)

## 2. Add annotations
```
cat <<EOF > k8s/base/nginx-ingress/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-ingress-controller
  namespace: nginx-ingress
  annotations:
    # Available annotations: https://learn.microsoft.com/en-us/azure/aks/load-balancer-standard#customizations-via-kubernetes-annotations
    service.beta.kubernetes.io/azure-load-balancer-internal: true
    service.beta.kubernetes.io/azure-load-balancer-internal-subnet: snet-aks-ingress-controller-cibg-uaenorth-001 # 10.114.82.32/28
    # service.beta.kubernetes.io/azure-load-balancer-ipv4: '10.114.82.36'
EOF

cat <<EOF > k8s/base/nginx-ingress/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: nginx-ingress

resources:
- vendor/nginx-ingress.yaml

patches: # Usage: https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/patches/
- path: service.yaml

images: # Import: az acr import -n acrcibgdevuan5o5ufr --source docker.io/nginx/nginx-ingress:3.6.1
- name: nginx/nginx-ingress
  newName: acrcibgdevuan5o5ufr.azurecr.io/nginx/nginx-ingress
  newTag: 3.6.1
EOF
```

## 3. Validate kustomization
```
kustomize build k8s/base/nginx-ingress | yq eval 'select(.kind == "Service")' - 
```

## 4. Import image to ACR
```
az acr import -n acrcibgdevuan5o5ufr --source docker.io/nginx/nginx-ingress:3.6.1
```

## Checklist

 1. Import image `nginx/nginx-ingress:3.6.1` into ACR `acrcibgdevuan5o5ufr`
 2. Create namepsace `nginx-ingress`
 3. Create `rolebinding` in namespace `nginx-ingress`
 4. Add `Service` resource to `cibg/onboarding-orchestration-service`
 5. Add `Ingress` resource to `cibg/onboarding-orchestration-service`
 6. Merge pull request and deploy ingress

## Links:
 - https://learn.microsoft.com/en-us/azure/aks/app-routing-nginx-configuration
 - https://learn.microsoft.com/en-us/azure/aks/load-balancer-standard#customizations-via-kubernetes-annotations
 - https://docs.nginx.com/nginx-ingress-controller/installation/installing-nic/installation-with-helm/
