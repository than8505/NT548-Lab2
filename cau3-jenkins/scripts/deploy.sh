#!/usr/bin/env bash
# =============================================================================
# Deploy ứng dụng Aurapan lên k3s bằng kustomize
#   - Service vừa build (BUILT_SERVICES) -> dùng tag mới IMAGE_TAG
#   - Service không đổi -> giữ nguyên tag đang chạy trên cluster (không redeploy)
# Biến môi trường:
#   KUBECONFIG      (bắt buộc) kubeconfig của ServiceAccount jenkins-deployer
#   REGISTRY        (bắt buộc) vd docker.io/<dockerhub-user>
#   IMAGE_TAG       (bắt buộc) vd 15-a1b2c3d
#   JWT_KEY         (bắt buộc) secret ký JWT cho các service
#   BUILT_SERVICES  danh sách service vừa build, phân cách dấu phẩy
#   NAMESPACE       mặc định aurapan
#   STRIPE_KEY, PAYPAL_CLIENT_ID  (tùy chọn, mặc định giá trị test giả)
# =============================================================================
set -euo pipefail

: "${KUBECONFIG:?Thiếu KUBECONFIG}"
: "${REGISTRY:?Thiếu REGISTRY}"
: "${IMAGE_TAG:?Thiếu IMAGE_TAG}"
: "${JWT_KEY:?Thiếu JWT_KEY}"
NS="${NAMESPACE:-aurapan}"
BUILT=",${BUILT_SERVICES:-},"
ALL_SERVICES="client user product order payment expiration"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$ROOT/.deploy"
rm -rf "$OVERLAY" && mkdir -p "$OVERLAY"

echo ">>> Kiểm tra kết nối cluster"
kubectl version --client=false -o yaml | grep -E 'gitVersion' || true
kubectl -n "$NS" get serviceaccount default > /dev/null

echo ">>> Tạo/cập nhật Secret app-secrets"
kubectl -n "$NS" create secret generic app-secrets \
  --from-literal=JWT_KEY="$JWT_KEY" \
  --from-literal=STRIPE_KEY="${STRIPE_KEY:-sk_test_lab2_dummy}" \
  --from-literal=PAYPAL_CLIENT_ID="${PAYPAL_CLIENT_ID:-sb}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">>> Sinh overlay kustomize"
{
  echo "apiVersion: kustomize.config.k8s.io/v1beta1"
  echo "kind: Kustomization"
  echo "resources:"
  echo "  - ../k8s/base"
  echo "images:"
  for svc in $ALL_SERVICES; do
    if [[ "$BUILT" == *",$svc,"* ]]; then
      tag="$IMAGE_TAG"
    else
      current="$(kubectl -n "$NS" get deploy "${svc}-depl" \
        -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
      tag="${current##*:}"
      if [[ -z "$current" || "$tag" == "$current" || "$current" != "$REGISTRY/"* ]]; then
        tag="latest"
      fi
    fi
    echo "  - name: aurapan/$svc"
    echo "    newName: $REGISTRY/aurapan-$svc"
    echo "    newTag: \"$tag\""
    printf '    %-11s -> %s\n' "$svc" "$REGISTRY/aurapan-$svc:$tag" >&2
  done
} > "$OVERLAY/kustomization.yaml"

kubectl kustomize "$OVERLAY" > "$OVERLAY/rendered.yaml"
echo ">>> Áp dụng manifest (server-side dry-run trước)"
kubectl apply -k "$OVERLAY" --dry-run=server > /dev/null
kubectl apply -k "$OVERLAY"

echo ">>> Chờ rollout"
for d in $(kubectl -n "$NS" get deploy -o name); do
  kubectl -n "$NS" rollout status "$d" --timeout=600s
done

echo ">>> Trạng thái sau deploy"
kubectl -n "$NS" get deploy,pods,svc,ingress -o wide
