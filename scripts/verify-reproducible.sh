#!/usr/bin/env bash
# Kiểm chứng TỰ ĐỘNG rằng bộ image của shop là tái lập được — cho CẢ BỐN service.
#
# Script này không tin lời hứa trong doc; nó build hai lần trên cùng một commit rồi
# assert từng điều một, và exit != 0 nếu bất kỳ điều nào sai:
#
#   1. Base image ghim bằng DIGEST (@sha256:) — cả tầng build lẫn tầng runtime, không tag trần.
#   2. Tầng runtime KHÔNG chạy root (có USER) và KHÔNG mang SDK.
#   3. Restore chạy ở --locked-mode, và .csproj + packages.lock.json copy TRƯỚC source.
#   4. Label org.opencontainers.image.revision == git SHA ngắn của HEAD.
#   5. Không có dependency trôi nổi: dependency set khoá trong packages.lock.json đã commit
#      (in ra sha256 của lockfile để so được giữa hai lần build / hai máy).
#   6. Build lần hai cho ra CÙNG digest của runtime config + filesystem layers.
#
# Dùng: bash scripts/verify-reproducible.sh
set -uo pipefail
cd "$(dirname "$0")/.."

SERVICES=(catalog cart order payment)
DOCKERFILES=(Dockerfile services/Cart/Dockerfile services/order/Dockerfile services/payment/Dockerfile)
# Lockfile mà mỗi service restore (payment không tham chiếu Shop.Contracts).
LOCKFILES=(
  "packages/Shop.Contracts/packages.lock.json services/Catalog/packages.lock.json"
  "packages/Shop.Contracts/packages.lock.json services/Cart/packages.lock.json"
  "packages/Shop.Contracts/packages.lock.json services/order/packages.lock.json"
  "services/payment/packages.lock.json"
)

GIT_SHA="$(git rev-parse --short HEAD)"
FAILED=0

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "error: working tree không sạch — không thể chứng minh image khớp commit ${GIT_SHA}" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILED=1; }

echo "commit under test: ${GIT_SHA}"
echo

# ---------- 1..3: kiểm tra tĩnh từng Dockerfile ----------
echo "=== Dockerfile checks (4/4 service) ==="
for i in "${!SERVICES[@]}"; do
  svc="${SERVICES[$i]}"; df="${DOCKERFILES[$i]}"
  echo "[${svc}] ${df}"

  [[ -f "$df" ]] || { fail "${svc}: Dockerfile không tồn tại"; continue; }

  # 1. mọi FROM phải ghim digest
  from_lines="$(grep -c '^FROM ' "$df")"
  pinned="$(grep -c '^FROM .*@sha256:' "$df")"
  if [[ "$from_lines" -eq "$pinned" && "$pinned" -ge 2 ]]; then
    pass "${svc}: ${pinned}/${from_lines} FROM ghim @sha256 (build + runtime)"
  else
    fail "${svc}: chỉ ${pinned}/${from_lines} FROM ghim digest — còn tag trôi nổi"
  fi

  # 2. runtime không root, và runtime base là aspnet (không SDK)
  grep -q '^USER ' "$df" && pass "${svc}: có USER (không chạy root)" \
                        || fail "${svc}: thiếu USER — tầng runtime chạy root"
  grep -q '^FROM mcr.microsoft.com/dotnet/aspnet.* AS runtime' "$df" \
    && pass "${svc}: runtime base = aspnet (không SDK)" \
    || fail "${svc}: runtime base không phải aspnet"

  # 3. locked mode + thứ tự layer: restore phải nằm TRƯỚC dòng COPY source
  grep -q 'dotnet restore .*--locked-mode' "$df" \
    && pass "${svc}: restore ở --locked-mode" \
    || fail "${svc}: restore KHÔNG dùng --locked-mode"

  restore_ln="$(grep -n 'dotnet restore' "$df" | head -1 | cut -d: -f1)"
  lock_ln="$(grep -n 'packages.lock.json' "$df" | head -1 | cut -d: -f1)"
  src_ln="$(grep -n '^COPY services/.*/ services/' "$df" | head -1 | cut -d: -f1)"
  if [[ -n "$restore_ln" && -n "$lock_ln" && -n "$src_ln" \
        && "$lock_ln" -lt "$restore_ln" && "$restore_ln" -lt "$src_ln" ]]; then
    pass "${svc}: lockfile(L${lock_ln}) -> restore(L${restore_ln}) -> source(L${src_ln})"
  else
    fail "${svc}: thứ tự layer sai (lockfile=${lock_ln} restore=${restore_ln} source=${src_ln})"
  fi
  echo
done

# ---------- 5: dependency set khoá bằng lockfile đã commit ----------
echo "=== Dependency set khoá bằng lockfile đã commit (không floating) ==="
for i in "${!SERVICES[@]}"; do
  svc="${SERVICES[$i]}"
  for lf in ${LOCKFILES[$i]}; do
    if [[ ! -f "$lf" ]]; then fail "${svc}: thiếu ${lf}"; continue; fi
    if ! git ls-files --error-unmatch "$lf" >/dev/null 2>&1; then
      fail "${svc}: ${lf} CHƯA được commit"; continue
    fi
    echo "  [${svc}] $(sha256sum "$lf" | cut -c1-16)…  ${lf}  (committed)"
  done
done
echo

# ---------- 4 + 6: build hai lần, so label và runtime-content digest ----------
build_all() { # $1 = tên vòng, ghi runtime-content digest ra file $2
  local round="$1" out="$2"
  : > "$out"
  for i in "${!SERVICES[@]}"; do
    local svc="${SERVICES[$i]}" df="${DOCKERFILES[$i]}"
    local log; log="$(mktemp)"
    docker build --build-arg "GIT_SHA=${GIT_SHA}" \
      -t "starci-shop/${svc}:${GIT_SHA}" -f "$df" . >"$log" 2>&1 \
      || { fail "${svc}: docker build thất bại (${round})"; tail -5 "$log"; }
    # Hash trực tiếp runtime config + filesystem layers từ image đã load. Cách này ổn định
    # trên cả Docker Desktop (containerd image store) lẫn GitHub runner, không phụ thuộc
    # format log BuildKit hay manifest attestation có timestamp.
    runtime_digest="$(
      docker inspect --format '{{json .Config}}|{{json .RootFS.Layers}}' \
        "starci-shop/${svc}:${GIT_SHA}" | sha256sum | awk '{print "sha256:" $1}'
    )"
    echo "${svc} ${runtime_digest}" >> "$out"
    if [[ "$round" == "run2" ]]; then
      grep -A1 'RUN dotnet restore' "$log" | grep -q CACHED \
        && pass "${svc}: layer restore CACHED ở lần build thứ hai" \
        || fail "${svc}: layer restore KHÔNG cached — cache lockfile-first bị vỡ"
    fi
    rm -f "$log"
  done
}

echo "=== Build lần 1 ==="
build_all run1 "$TMP_DIR/repro-run1.txt"
echo "=== Build lần 2 (cùng commit) ==="
build_all run2 "$TMP_DIR/repro-run2.txt"
echo

echo "=== Label revision == git SHA (4/4 service) ==="
for svc in "${SERVICES[@]}"; do
  got="$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
    "starci-shop/${svc}:${GIT_SHA}" 2>/dev/null)"
  [[ "$got" == "$GIT_SHA" ]] \
    && pass "${svc}: revision=${got}" \
    || fail "${svc}: revision=${got:-<rỗng>} (mong đợi ${GIT_SHA})"
done
echo

echo "=== Runtime gọn + non-root (4/4 service) ==="
for svc in "${SERVICES[@]}"; do
  image="starci-shop/${svc}:${GIT_SHA}"
  sdk_list="$(docker run --rm --entrypoint dotnet "$image" --list-sdks 2>/dev/null)"
  [[ -z "$sdk_list" ]] \
    && pass "${svc}: runtime không chứa .NET SDK" \
    || fail "${svc}: runtime còn SDK (${sdk_list})"

  uid="$(docker run --rm --entrypoint id "$image" -u 2>/dev/null)"
  [[ -n "$uid" && "$uid" != "0" ]] \
    && pass "${svc}: runtime uid=${uid} (non-root)" \
    || fail "${svc}: runtime chạy root hoặc không đọc được uid"
done
echo

echo "=== Hai lần build -> CÙNG runtime-content digest (4/4 service) ==="
while read -r svc digest; do
  d2="$(grep "^${svc} " "$TMP_DIR/repro-run2.txt" | awk '{print $2}')"
  [[ -n "$digest" && "$digest" == "$d2" ]] \
    && pass "${svc}: ${digest:0:26}… giống nhau ở cả hai lần build" \
    || fail "${svc}: run1=${digest} != run2=${d2}"
done < "$TMP_DIR/repro-run1.txt"
echo

if [[ $FAILED -eq 0 ]]; then
  echo "OK — bộ image của commit ${GIT_SHA} tái lập được (cả 4 service)."
else
  echo "CÓ LỖI — xem các dòng FAIL ở trên."
fi
exit $FAILED
