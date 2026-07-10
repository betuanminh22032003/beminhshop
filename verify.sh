#!/usr/bin/env bash
# verify.sh — kiểm chứng cơ học (đọc source files) các yêu cầu env-driven config
# cho hai service Catalog & Cart. Không cần build/chạy — chỉ đọc file nguồn.
#
#   Chạy:   bash verify.sh
#   Kết quả: exit 0 nếu TẤT CẢ pass, exit 1 nếu có bất kỳ FAIL nào.
set -u
cd "$(dirname "$0")"

fail=0
pass() { printf 'PASS  %s\n' "$1"; }
die()  { printf 'FAIL  %s\n' "$1"; fail=1; }

# must <desc> <regex> <file>       : file PHẢI khớp regex
must() { if grep -Eq "$2" "$3"; then pass "$1"; else die "$1"; fi; }
# nomatch <desc> <regex> <file...> : các file PHẢI KHÔNG khớp regex
nomatch() {
  local desc="$1" pat="$2"; shift 2
  if grep -Eq "$pat" "$@"; then die "$desc"; else pass "$desc"; fi
}

echo "== Catalog & Cart: entrypoint đọc env qua Config.Load, không hardcode cổng =="
for svc in Catalog Cart; do
  P="services/$svc/Program.cs"
  C="services/$svc/Config.cs"
  must    "$svc/Program.cs: gọi Config.Load(...)"                 'Config\.Load\('                              "$P"
  must    "$svc/Program.cs: UseUrls dùng biến config.Port"       'UseUrls\(.*config\.Port'                     "$P"
  nomatch "$svc/Program.cs: UseUrls KHÔNG chứa số cứng"          'UseUrls\([^)]*[0-9]'                         "$P"
  must    "$svc/Program.cs: log/health dùng config.ServiceName"  'config\.ServiceName'                         "$P"
  must    "$svc/Config.cs: đọc PORT từ environment"              'GetEnvironmentVariable\("PORT"\)'            "$C"
  must    "$svc/Config.cs: đọc SERVICE_NAME từ environment"      'GetEnvironmentVariable\("SERVICE_NAME"\)'    "$C"
  must    "$svc/Config.cs: ném lỗi khi PORT không parse được"    'InvalidOperationException'                   "$C"
  must    "$svc/Config.cs: namespace riêng ($svc)"              "^namespace $svc;"                            "$C"
done

echo ""
echo "== Ranh giới: mỗi service độc lập, không dùng chung logic =="
nomatch "Không ProjectReference chéo giữa Catalog/Cart" 'ProjectReference' \
        services/Catalog/Catalog.csproj services/Cart/Cart.csproj
if ls services 2>/dev/null | grep -Eiq '^(shared|common|core|libs)$'; then
  die "Không có thư mục service dùng chung (shared/common/core/libs)"
else
  pass "Không có thư mục service dùng chung (shared/common/core/libs)"
fi

echo ""
if [ "$fail" -eq 0 ]; then
  echo "==> TẤT CẢ PASS"
else
  echo "==> CÓ FAIL"
fi
exit $fail
