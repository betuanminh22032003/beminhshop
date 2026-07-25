#!/usr/bin/env bash
# Phát hành CẢ SHOP dưới dạng bộ image tái lập được.
#
# Mỗi image được tag bằng ĐÚNG commit sinh ra nó (git SHA ngắn) và tự khai commit đó
# trong OCI label org.opencontainers.image.revision. Không có `latest` trôi nổi:
# `latest` (nếu có) chỉ là alias trỏ tới tag SHA vừa build.
#
# Vì sao build lại rất nhanh: Dockerfile copy .csproj + packages.lock.json TRƯỚC source,
# nên layer `dotnet restore --locked-mode` giữ cache khi chỉ có code đổi -> lần build thứ
# hai trên cùng một commit in ra CACHED ở layer restore.
#
# Dùng:
#   bash scripts/build-images.sh              # build cả 4 service, tag = SHA ngắn
#   bash scripts/build-images.sh --latest     # thêm alias :latest trỏ cùng image
#
# Chạy hai lần trên cùng một commit ⇒ cùng một bộ triển khai (base ghim digest,
# NuGet ghim lockfile).
set -euo pipefail

cd "$(dirname "$0")/.."

if ! GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null)"; then
  echo "error: không phải git repo — không có commit thì không tag bất biến được" >&2
  exit 1
fi

# Cây làm việc bẩn = image sẽ KHÔNG khớp commit được tag. Cảnh báo, không chặn (dev tiện).
if ! git diff-index --quiet HEAD --; then
  echo "warn: working tree có thay đổi chưa commit — image tag $GIT_SHA sẽ KHÔNG khớp commit đó" >&2
fi

TAG_LATEST=0
[[ "${1:-}" == "--latest" ]] && TAG_LATEST=1

# Tên service -> Dockerfile. Cả bốn build với context = GỐC repo (Catalog/Cart/order
# tham chiếu packages/Shop.Contracts; payment giữ cùng hợp đồng cho đồng nhất).
SERVICES=(catalog cart order payment)
DOCKERFILES=(Dockerfile services/Cart/Dockerfile services/order/Dockerfile services/payment/Dockerfile)

for i in "${!SERVICES[@]}"; do
  svc="${SERVICES[$i]}"
  dockerfile="${DOCKERFILES[$i]}"
  image="starci-shop/${svc}:${GIT_SHA}"

  echo "==> build ${image}  (-f ${dockerfile})"
  docker build \
    --build-arg "GIT_SHA=${GIT_SHA}" \
    -t "${image}" \
    -f "${dockerfile}" \
    .

  if [[ $TAG_LATEST -eq 1 ]]; then
    # latest CHỈ là alias — artifact bất biến vẫn là tag SHA.
    docker tag "${image}" "starci-shop/${svc}:latest"
    echo "    tagged starci-shop/${svc}:latest -> ${GIT_SHA}"
  fi

  echo "    built ${image}"
done

echo
echo "Bộ image của commit ${GIT_SHA}:"
docker images --filter "reference=starci-shop/*:${GIT_SHA}" \
  --format '  {{.Repository}}:{{.Tag}}  {{.Size}}  (id {{.ID}})'

echo
echo "Kiểm chứng revision nướng trong image:"
for svc in "${SERVICES[@]}"; do
  revision="$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
    "starci-shop/${svc}:${GIT_SHA}")"
  echo "  starci-shop/${svc}:${GIT_SHA} -> revision=${revision}"
done
