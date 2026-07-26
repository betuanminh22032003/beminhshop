#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."

SERVICES=(catalog cart order payment)
DOCKERFILES=(Dockerfile services/Cart/Dockerfile services/order/Dockerfile services/payment/Dockerfile)
LOCKFILES=(
  "packages/Shop.Contracts/packages.lock.json services/Catalog/packages.lock.json"
  "packages/Shop.Contracts/packages.lock.json services/Cart/packages.lock.json"
  "packages/Shop.Contracts/packages.lock.json services/order/packages.lock.json"
  "services/payment/packages.lock.json"
)
GIT_SHA="$(git rev-parse --short HEAD)"
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
  echo "error: working tree must be clean to verify commit ${GIT_SHA}" >&2
  exit 1
}

FAILED=0
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILED=1; }

echo "=== Complete Dockerfile checks: catalog, cart, order, payment ==="
for i in "${!SERVICES[@]}"; do
  service="${SERVICES[$i]}"
  dockerfile="${DOCKERFILES[$i]}"
  echo "[${service}] ${dockerfile}"

  from_count="$(grep -c '^FROM ' "$dockerfile")"
  pinned_count="$(grep -c '^FROM .*@sha256:' "$dockerfile")"
  [[ "$from_count" -eq 2 && "$pinned_count" -eq 2 ]] \
    && pass "2/2 base images pinned by digest" \
    || fail "${pinned_count}/${from_count} base images pinned by digest"
  grep -q '^FROM mcr.microsoft.com/dotnet/aspnet.* AS runtime$' "$dockerfile" \
    && pass "runtime uses ASP.NET only (no SDK)" || fail "runtime is not ASP.NET-only"
  grep -q '^USER \$APP_UID$' "$dockerfile" \
    && pass 'runtime uses non-root $APP_UID' || fail 'missing USER $APP_UID'
  grep -q 'dotnet restore .*--locked-mode' "$dockerfile" \
    && pass "NuGet restore uses --locked-mode" || fail "restore is not locked"

  lock_line="$(grep -n '^COPY .*packages.lock.json' "$dockerfile" | head -1 | cut -d: -f1)"
  restore_line="$(grep -n '^RUN dotnet restore' "$dockerfile" | head -1 | cut -d: -f1)"
  source_line="$(grep -n '^COPY services/.*/ services/' "$dockerfile" | head -1 | cut -d: -f1)"
  [[ -n "$lock_line" && -n "$restore_line" && -n "$source_line" \
     && "$lock_line" -lt "$restore_line" && "$restore_line" -lt "$source_line" ]] \
    && pass "lockfile(L${lock_line}) -> restore(L${restore_line}) -> source(L${source_line})" \
    || fail "dependency layer ordering is invalid"

  for lockfile in ${LOCKFILES[$i]}; do
    git ls-files --error-unmatch "$lockfile" >/dev/null 2>&1 \
      && pass "${lockfile} is committed" || fail "${lockfile} is not committed"
  done
done

build_all() {
  local round="$1" digest_file="$2"
  : > "$digest_file"
  for i in "${!SERVICES[@]}"; do
    local service="${SERVICES[$i]}" log="$TMP_DIR/${round}-${SERVICES[$i]}.log"
    local image="starci-shop/${service}:${GIT_SHA}"
    if ! docker build --build-arg "GIT_SHA=${GIT_SHA}" --tag "$image" \
      --file "${DOCKERFILES[$i]}" . >"$log" 2>&1; then
      fail "${service}: docker build failed in ${round}"
      tail -10 "$log"
      continue
    fi
    docker inspect --format '{{json .Config}}|{{json .RootFS.Layers}}' "$image" \
      | sha256sum | awk -v service="$service" '{print service, "sha256:" $1}' >> "$digest_file"
    if [[ "$round" == "run2" ]]; then
      grep -A1 'RUN dotnet restore' "$log" | grep -q CACHED \
        && pass "${service}: restore layer CACHED on rebuild" \
        || fail "${service}: restore layer was not cached"
    fi
  done
}

echo "=== Build all four images twice at ${GIT_SHA} ==="
build_all run1 "$TMP_DIR/run1.txt"
build_all run2 "$TMP_DIR/run2.txt"

echo "=== docker images + OCI revision + runtime checks ==="
docker images --filter "reference=starci-shop/*:${GIT_SHA}" \
  --format '  {{.Repository}}:{{.Tag}} {{.Size}} {{.ID}}'
for service in "${SERVICES[@]}"; do
  image="starci-shop/${service}:${GIT_SHA}"
  revision="$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image" 2>/dev/null)"
  [[ "$revision" == "$GIT_SHA" ]] \
    && pass "${service}: OCI revision=${revision}" || fail "${service}: bad OCI revision=${revision}"
  [[ -z "$(docker run --rm --entrypoint dotnet "$image" --list-sdks 2>/dev/null)" ]] \
    && pass "${service}: runtime contains no SDK" || fail "${service}: runtime contains SDK"
  uid="$(docker run --rm --entrypoint id "$image" -u 2>/dev/null)"
  [[ -n "$uid" && "$uid" != "0" ]] \
    && pass "${service}: runtime uid=${uid}" || fail "${service}: runtime is root"
done

echo "=== Functional image digests match across both builds ==="
while read -r service digest1; do
  digest2="$(awk -v service="$service" '$1 == service {print $2}' "$TMP_DIR/run2.txt")"
  [[ -n "$digest1" && "$digest1" == "$digest2" ]] \
    && pass "${service}: ${digest1}" || fail "${service}: ${digest1} != ${digest2}"
done < "$TMP_DIR/run1.txt"

[[ $FAILED -eq 0 ]] \
  && echo "OK: reproducible image bundle verified for all 4 services." \
  || echo "FAILED: reproducible image verification failed."
exit "$FAILED"
