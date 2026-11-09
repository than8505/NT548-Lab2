#!/bin/bash
# =============================================================================
# User-data cho node k3s (Terraform templatefile)
#   1. Cài k3s (kèm Traefik ingress + ServiceLB + local-path storage)
#   2. Tạo namespace "aurapan" + ServiceAccount "jenkins-deployer" (quyền admin
#      CHỈ trong namespace này)
#   3. Sinh kubeconfig cho Jenkins và đẩy lên S3 (mã hóa) cho máy Jenkins tải về
# Log: /var/log/user-data.log
# =============================================================================
set -euxo pipefail
exec > >(tee -a /var/log/user-data.log) 2>&1
export DEBIAN_FRONTEND=noninteractive

IMDS=http://169.254.169.254/latest
TOKEN=$(curl -sX PUT "$IMDS/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 600")
md() { curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "$IMDS/meta-data/$1"; }
PRIVATE_IP=$(md local-ipv4)
PUBLIC_IP=$(md public-ipv4 || true)

apt-get update -y
apt-get install -y curl jq
snap install aws-cli --classic

# ---------------------------------------------------------------------------
# 1. k3s
# ---------------------------------------------------------------------------
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -s - server \
  --write-kubeconfig-mode 0644 \
  --node-ip "$PRIVATE_IP" \
  --node-external-ip "$PUBLIC_IP" \
  --tls-san "$PRIVATE_IP" \
  --tls-san "$PUBLIC_IP"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
until kubectl get nodes 2>/dev/null | grep -q ' Ready'; do sleep 5; done
until kubectl -n kube-system get deploy traefik >/dev/null 2>&1; do sleep 5; done
kubectl -n kube-system rollout status deploy/traefik --timeout=300s

# ---------------------------------------------------------------------------
# 2. Namespace + ServiceAccount cho Jenkins (least privilege)
# ---------------------------------------------------------------------------
kubectl create namespace aurapan --dry-run=client -o yaml | kubectl apply -f -
kubectl -n aurapan create serviceaccount jenkins-deployer --dry-run=client -o yaml | kubectl apply -f -
kubectl -n aurapan create rolebinding jenkins-deployer-admin \
  --clusterrole=admin --serviceaccount=aurapan:jenkins-deployer \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-deployer-token
  namespace: aurapan
  annotations:
    kubernetes.io/service-account.name: jenkins-deployer
type: kubernetes.io/service-account-token
YAML

SA_TOKEN=""
until [ -n "$SA_TOKEN" ]; do
  sleep 2
  SA_TOKEN=$(kubectl -n aurapan get secret jenkins-deployer-token -o jsonpath='{.data.token}' | base64 -d || true)
done
CA_DATA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

make_kubeconfig() {
cat <<KCFG
apiVersion: v1
kind: Config
clusters:
  - name: k3s-lab2
    cluster:
      server: https://$1:6443
      certificate-authority-data: $CA_DATA
users:
  - name: jenkins-deployer
    user:
      token: $SA_TOKEN
contexts:
  - name: jenkins-deployer@k3s-lab2
    context:
      cluster: k3s-lab2
      user: jenkins-deployer
      namespace: aurapan
current-context: jenkins-deployer@k3s-lab2
KCFG
}

# ---------------------------------------------------------------------------
# 3. Đẩy kubeconfig (dùng private IP) lên S3 cho máy Jenkins
# ---------------------------------------------------------------------------
umask 077
make_kubeconfig "$PRIVATE_IP" > /root/kubeconfig-jenkins
/snap/bin/aws s3 cp /root/kubeconfig-jenkins "s3://${kubeconfig_bucket}/jenkins/kubeconfig" \
  --region "${aws_region}" --sse AES256

# Kubeconfig admin cho user ubuntu (kubectl trên node / scp về máy cá nhân)
mkdir -p /home/ubuntu/.kube
sed "s/127.0.0.1/$PUBLIC_IP/" /etc/rancher/k3s/k3s.yaml > /home/ubuntu/.kube/config-public
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
chmod 600 /home/ubuntu/.kube/config /home/ubuntu/.kube/config-public
echo 'export KUBECONFIG=$HOME/.kube/config' >> /home/ubuntu/.bashrc

touch /var/lib/lab2-k3s-ready
echo "k3s READY: private=$PRIVATE_IP public=$PUBLIC_IP"
