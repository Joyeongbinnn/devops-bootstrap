#!/usr/bin/env bash
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC="server --disable traefik --write-kubeconfig-mode=644" sh -
sudo kubectl get node -o wide

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

# 3) ClusterIssuer 적용 (플레이스홀더 값 바꾸지 말고 템플릿으로 보관해도 됨)
kubectl apply -f infra/k8s/11-cluster-issuer-route53.yaml

# NGINX Ingress Controller (k3s에서는 LoadBalancer 타입 권장: ServiceLB가 붙음)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.ingressClass=nginx \
  --set controller.ingressClassResource.name=nginx \
  --set controller.ingressClassResource.controllerValue="k8s.io/ingress-nginx" \
  --set controller.ingressClassResource.default=false \
  --set controller.service.type=LoadBalancer
# 준비 대기
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller
kubectl -n ingress-nginx get svc ingress-nginx-controller



# Argo CD
aws configure

sudo kubectl create namespace argocd
sudo kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f k8s/20-argocd/ing-argocd.yaml
kubectl -n argocd rollout status deployment/argocd-server
 
kubectl -n soboro create secret docker-registry ecr-docker \
  --docker-server=awsidnumber.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region us-east-1)" \
  --docker-email=dummy@example.com

crontab -e
0 */11 * * * /usr/local/bin/ecr-refresh.sh >> /var/log/ecr-refresh.log 2>&1

sudo nano /usr/local/bin/ecr-refresh.sh
#!/bin/bash 크론잡만들기
AWS_REGION=us-east-1
ECR_REG=528920766011.dkr.ecr.${AWS_REGION}.amazonaws.com

PASS="$(aws ecr get-login-password --region ${AWS_REGION})"
kubectl -n soboro create secret docker-registry ecr-docker \
  --docker-server="${ECR_REG}" \
  --docker-username="AWS" \
  --docker-password="${PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

##여기까지

sudo chmod +x /usr/local/bin/ecr-refresh.sh

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prom-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f infra/k8s/21-monitoring/kube-prom-stack-values.yaml