#!/bin/bash
# =============================================================================
# User-data cho máy Jenkins (Terraform templatefile)
#   1. Cài Docker Engine + compose plugin, cấu hình kernel cho SonarQube, swap
#   2. Clone repo lab vào /opt/lab2
#   3. Tải kubeconfig (do node k3s đẩy lên S3) vào jenkins/secrets/kubeconfig
#   4. Tạo file .env với các giá trị tự động (bạn chỉ điền Docker Hub + mật khẩu)
# Sau khi máy chạy xong (~5 phút): SSH vào, điền .env rồi chạy ./bootstrap.sh
# Log: /var/log/user-data.log
# =============================================================================
set -euxo pipefail
exec > >(tee -a /var/log/user-data.log) 2>&1
export DEBIAN_FRONTEND=noninteractive

IMDS=http://169.254.169.254/latest
TOKEN=$(curl -sX PUT "$IMDS/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "$IMDS/meta-data/public-ipv4")

# ---------------------------------------------------------------------------
# 1. Docker + yêu cầu hệ thống của SonarQube
# ---------------------------------------------------------------------------
apt-get update -y
apt-get install -y ca-certificates curl git jq openssl
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
usermod -aG docker ubuntu

cat > /etc/sysctl.d/99-sonarqube.conf <<SYSCTL
vm.max_map_count=524288
fs.file-max=131072
SYSCTL
sysctl --system

# Swap 4GB để tránh OOM khi build Next.js song song với SonarQube
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

snap install aws-cli --classic

# ---------------------------------------------------------------------------
# 2. Mã nguồn lab
# ---------------------------------------------------------------------------
git clone --branch "${lab_repo_branch}" "${lab_repo_url}" /opt/lab2
JDIR=/opt/lab2/cau3-jenkins/jenkins
mkdir -p /var/jenkins_home "$JDIR/secrets"
chown 1000:1000 /var/jenkins_home

# ---------------------------------------------------------------------------
# 3. Kubeconfig từ S3 (chờ tối đa ~20 phút cho node k3s khởi tạo)
# ---------------------------------------------------------------------------
for i in $(seq 1 120); do
  if /snap/bin/aws s3 cp "s3://${kubeconfig_bucket}/jenkins/kubeconfig" "$JDIR/secrets/kubeconfig" \
       --region "${aws_region}"; then
    break
  fi
  echo "Chưa có kubeconfig, thử lại ($i)..."; sleep 10
done
chmod 600 "$JDIR/secrets/kubeconfig" || true

# ---------------------------------------------------------------------------
# 4. File .env (giá trị tự động)
# ---------------------------------------------------------------------------
cp "$JDIR/.env.example" "$JDIR/.env"
DOCKER_GID=$(getent group docker | cut -d: -f3)
sed -i \
  -e "s|^DOCKER_GID=.*|DOCKER_GID=$DOCKER_GID|" \
  -e "s|^K3S_HOST=.*|K3S_HOST=${k3s_private_ip}|" \
  -e "s|^JENKINS_URL=.*|JENKINS_URL=http://$PUBLIC_IP:8080/|" \
  -e "s|^LAB_REPO_URL=.*|LAB_REPO_URL=${lab_repo_url}|" \
  -e "s|^LAB_REPO_BRANCH=.*|LAB_REPO_BRANCH=${lab_repo_branch}|" \
  "$JDIR/.env"
chmod 600 "$JDIR/.env"
# user ubuntu (uid 1000) trùng uid với user jenkins trong container
chown -R ubuntu:ubuntu /opt/lab2

# Kéo trước các image dùng trong pipeline để lần build đầu nhanh hơn
for img in jenkins/jenkins:lts-jdk21 sonarqube:community postgres:16-alpine \
           node:20-bullseye sonarsource/sonar-scanner-cli:11 aquasec/trivy:0.58.1; do
  docker pull "$img" || true
done

touch /var/lib/lab2-jenkins-ready
echo "Jenkins host READY - tiếp theo: điền $JDIR/.env rồi chạy $JDIR/bootstrap.sh"
