#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null)" || {
  echo "error: a git commit is required" >&2
  exit 1
}
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
  echo "error: working tree must be clean before tagging ${GIT_SHA}" >&2
  exit 1
}

TAG_LATEST=0
case "${1:-}" in
  "") ;;
  --latest) TAG_LATEST=1 ;;
  *) echo "usage: bash scripts/build-images.sh [--latest]" >&2; exit 2 ;;
esac

SERVICES=(catalog cart order payment)
DOCKERFILES=(Dockerfile services/Cart/Dockerfile services/order/Dockerfile services/payment/Dockerfile)

for i in "${!SERVICES[@]}"; do
  service="${SERVICES[$i]}"
  image="starci-shop/${service}:${GIT_SHA}"
  docker build \
    --build-arg "GIT_SHA=${GIT_SHA}" \
    --tag "${image}" \
    --file "${DOCKERFILES[$i]}" \
    .
  [[ $TAG_LATEST -eq 0 ]] || docker tag "${image}" "starci-shop/${service}:latest"
done

echo "Images for commit ${GIT_SHA}:"
docker images --filter "reference=starci-shop/*:${GIT_SHA}" \
  --format '  {{.Repository}}:{{.Tag}} {{.Size}} {{.ID}}'

echo "OCI revisions:"
for service in "${SERVICES[@]}"; do
  image="starci-shop/${service}:${GIT_SHA}"
  revision="$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "${image}")"
  [[ "$revision" == "$GIT_SHA" ]] || {
    echo "error: ${image} revision=${revision}, expected=${GIT_SHA}" >&2
    exit 1
  }
  echo "  ${image} -> ${revision}"
done
