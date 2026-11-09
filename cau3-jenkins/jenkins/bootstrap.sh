#!/usr/bin/env bash
# =============================================================================
# Khởi tạo Jenkins + SonarQube trên máy Jenkins (chạy 1 lần, chạy lại an toàn)
#   1. Kiểm tra .env và kubeconfig
#   2. Bật SonarQube + PostgreSQL, đổi mật khẩu admin mặc định
#   3. Sinh token cho Jenkins, tạo webhook SonarQube -> Jenkins (Quality Gate)
#   4. Sinh JWT_KEY, build & bật Jenkins (JCasC tự tạo credentials + job)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

SONAR_URL="http://localhost:9000"
log() { printf '\n\033[1;34m>>> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mLỖI: %s\033[0m\n' "$*" >&2; exit 1; }

set_env() { # set_env KEY VALUE  -> ghi/cập nhật vào .env
  local k="$1" v="$2"
  if grep -q "^${k}=" .env; then
    sed -i "s|^${k}=.*|${k}=${v}|" .env
  else
    echo "${k}=${v}" >> .env
  fi
}

# ---------------------------------------------------------------------------
log "1. Kiểm tra cấu hình"
[[ -f .env ]] || die "Chưa có file .env (cp .env.example .env rồi điền giá trị)"
set -a; . ./.env; set +a
for v in DOCKERHUB_USER DOCKERHUB_TOKEN JENKINS_ADMIN_USER JENKINS_ADMIN_PASSWORD \
         SONAR_ADMIN_PASSWORD POSTGRES_PASSWORD DOCKER_GID K3S_HOST LAB_REPO_URL JENKINS_URL; do
  [[ -n "${!v:-}" ]] || die "Biến $v trong .env đang trống"
done
[[ ${#SONAR_ADMIN_PASSWORD} -ge 12 ]] || die "SONAR_ADMIN_PASSWORD phải >= 12 ký tự"
[[ -s secrets/kubeconfig ]] || die "Chưa có secrets/kubeconfig (xem README mục Câu 3)"
command -v jq >/dev/null || die "Cần cài jq"
chmod 600 .env

# ---------------------------------------------------------------------------
log "2. Khởi động SonarQube + PostgreSQL"
docker compose up -d sonar-db sonarqube
printf 'Đang chờ SonarQube sẵn sàng'
for _ in $(seq 1 90); do
  if curl -fs "$SONAR_URL/api/system/status" | grep -q '"status":"UP"'; then echo " -> UP"; break; fi
  printf '.'; sleep 5
done
curl -fs "$SONAR_URL/api/system/status" | grep -q '"status":"UP"' || die "SonarQube không lên (docker logs sonarqube)"

if curl -fs -u admin:admin "$SONAR_URL/api/authentication/validate" | grep -q '"valid":true'; then
  log "   Đổi mật khẩu admin mặc định của SonarQube"
  curl -fs -u admin:admin -X POST "$SONAR_URL/api/users/change_password" \
    --data-urlencode "login=admin" \
    --data-urlencode "previousPassword=admin" \
    --data-urlencode "password=${SONAR_ADMIN_PASSWORD}" \
    || die "Không đổi được mật khẩu (kiểm tra độ mạnh SONAR_ADMIN_PASSWORD)"
fi
AUTH="admin:${SONAR_ADMIN_PASSWORD}"
curl -fs -u "$AUTH" "$SONAR_URL/api/authentication/validate" | grep -q '"valid":true' \
  || die "Sai SONAR_ADMIN_PASSWORD"

# ---------------------------------------------------------------------------
log "3. Token + Webhook cho Jenkins"
if [[ -z "${SONAR_TOKEN:-}" ]]; then
  curl -fs -u "$AUTH" -X POST "$SONAR_URL/api/user_tokens/revoke" --data-urlencode "name=jenkins" >/dev/null || true
  SONAR_TOKEN="$(curl -fs -u "$AUTH" -X POST "$SONAR_URL/api/user_tokens/generate" \
    --data-urlencode "name=jenkins" | jq -r '.token')"
  [[ -n "$SONAR_TOKEN" && "$SONAR_TOKEN" != "null" ]] || die "Không sinh được Sonar token"
  set_env SONAR_TOKEN "$SONAR_TOKEN"
  echo "   Đã sinh SONAR_TOKEN và lưu vào .env"
fi

if ! curl -fs -u "$AUTH" "$SONAR_URL/api/webhooks/list" | jq -e '.webhooks[] | select(.name=="jenkins")' >/dev/null; then
  curl -fs -u "$AUTH" -X POST "$SONAR_URL/api/webhooks/create" \
    --data-urlencode "name=jenkins" \
    --data-urlencode "url=http://jenkins:8080/sonarqube-webhook/" >/dev/null
  echo "   Đã tạo webhook SonarQube -> http://jenkins:8080/sonarqube-webhook/"
fi

# ---------------------------------------------------------------------------
log "4. Build & khởi động Jenkins"
if [[ -z "${JWT_KEY:-}" ]]; then
  export JWT_KEY="$(openssl rand -hex 32)"
  set_env JWT_KEY "$JWT_KEY"
fi
export SONAR_TOKEN   # biến shell được ưu tiên hơn .env khi chạy docker compose
sudo mkdir -p /var/jenkins_home && sudo chown 1000:1000 /var/jenkins_home
docker compose up -d --build jenkins

printf 'Đang chờ Jenkins sẵn sàng'
for _ in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login || true)"
  if [[ "$code" == "200" ]]; then echo " -> OK"; break; fi
  printf '.'; sleep 5
done

cat <<EOF

=====================================================================
 Jenkins   : ${JENKINS_URL}   (user: ${JENKINS_ADMIN_USER})
 SonarQube : ${JENKINS_URL%:8080/}:9000   (user: admin)
 Job       : aurapan-microservices  -> bấm "Build with Parameters"
=====================================================================
EOF
