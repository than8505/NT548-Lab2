#!/usr/bin/env bash
# In ra danh sách service (phân cách dấu phẩy) có thay đổi giữa 2 commit.
# Dùng: detect-changes.sh <from-commit> <to-commit>
# Nếu không có from-commit (build đầu tiên) hoặc commit không tồn tại -> trả về tất cả.
set -euo pipefail
ALL="client,user,product,order,payment,expiration"
FROM="${1:-}"; TO="${2:-HEAD}"
APP_PREFIX="cau3-jenkins/app"

if [[ -z "$FROM" ]] || ! git cat-file -e "$FROM^{commit}" 2>/dev/null; then
  echo "$ALL"; exit 0
fi

changed=()
files="$(git diff --name-only "$FROM" "$TO")"
for svc in ${ALL//,/ }; do
  if grep -q "^$APP_PREFIX/$svc/" <<< "$files"; then changed+=("$svc"); fi
done
(IFS=,; echo "${changed[*]:-}")
