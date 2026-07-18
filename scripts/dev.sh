#!/usr/bin/env bash
# scripts/dev.sh — một lệnh để dựng cả đội lên (Catalog:5001, Cart:5002, order:5003).
# Mỗi service chạy như một tiến trình dotnet run riêng, log có tiền tố [<svc>].
# Nếu bất kỳ service nào thoát, hạ cả đội xuống.
set -euo pipefail
pids=()
for svc in Catalog Cart order; do
  echo "[dev] starting $svc"
  ( dotnet run --project "services/$svc" 2>&1 | sed "s/^/[$svc] /" ) &
  pids+=("$!")
done
trap 'kill ${pids[*]} 2>/dev/null' EXIT
wait -n "${pids[@]}"   # trả về khi tiến trình con đầu tiên thoát
echo "[dev] một service đã thoát — đang hạ cả đội"
