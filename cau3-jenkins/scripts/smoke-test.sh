#!/usr/bin/env bash
# Kiểm tra nhanh sau deploy qua Ingress (Traefik) của k3s
#   APP_URL  vd https://10.20.1.15  (Jenkins gọi bằng private IP của node k3s)
set -euo pipefail
APP_URL="${APP_URL:?Thiếu APP_URL}"
fail=0

check() {
  local path="$1" expect="$2" code=""
  for i in $(seq 1 30); do
    code="$(curl -sk -o /tmp/smoke.out -w '%{http_code}' "$APP_URL$path" || true)"
    [[ "$code" == "$expect" ]] && break
    sleep 10
  done
  if [[ "$code" == "$expect" ]]; then
    echo "PASS  GET $path -> $code  $(head -c 120 /tmp/smoke.out | tr -d '\n')"
  else
    echo "FAIL  GET $path -> $code (mong đợi $expect)"; fail=1
  fi
}

check /api/users/currentuser 200
check /api/products 200
check / 200

exit $fail
