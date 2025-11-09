# K3S_URL과 TOKEN은 master에서 확인: /var/lib/rancher/k3s/server/node-token
#마스터노드에서
sudo cat /var/lib/rancher/k3s/server/node-token
#워커노드에서
K3S_URL=${1:-"https://MASTER_PUBLIC_IP:6443"}
TOKEN=${2:-"REPLACE_ME"}
curl -sfL https://get.k3s.io | K3S_URL=$K3S_URL K3S_TOKEN=$TOKEN sh -
