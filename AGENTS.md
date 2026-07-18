# StarCi Shop — Hướng dẫn cho AI agent

Monorepo .NET chứa **bốn microservice độc lập**: Catalog, Cart, order, payment. Đây là bộ khung cho các milestone sau (container, database, gateway, saga, flash sale) — mọi thay đổi phải cắm vào khung này, không phá nó.

## Bố cục

```
starci-shop.slnx        # solution gốc — GỌI TÊN cả 4 project service, không dùng glob
README.md               # bản đồ service — ĐỌC TRƯỚC khi sửa bất kỳ service nào
scripts/                 # dev.sh (dựng Catalog+Cart+order cùng lúc), health.csx (probe /health)
services/
  Catalog/               # sản phẩm         (http://localhost:5001, cổng cứng qua app.Run + launchSettings)
  Cart/                  # giỏ hàng         (http://localhost:5002, cổng cứng qua app.Run + launchSettings)
  order/                 # đơn hàng         (http://localhost:5003, cổng cứng qua app.Run + launchSettings)
  payment/               # thanh toán       (http://localhost:5004, launchSettings — chưa đổi milestone này)
```

Mỗi service: một `.csproj` (`Microsoft.NET.Sdk.Web`, `net10.0`) + `Program.cs` riêng. ASP.NET Core minimal API. **Cả 4 service đều có `Properties/launchSettings.json`** khai báo `applicationUrl` cổng cố định (Catalog 5001, Cart 5002, order 5003, payment 5004) để `dotnet run` tự lên đúng cổng.

**Casing có chủ đích:** `Catalog`/`Cart` dùng PascalCase (thư mục, `.csproj`, namespace đều khớp `Catalog`/`Cart`) vì đã có `Config.cs` với `namespace Catalog;` / `namespace Cart;`. `order`/`payment` chưa được nâng cấp lên pattern này — đừng tự ý đổi tên chúng khi không có yêu cầu, và đừng "sửa cho đồng bộ" nếu task không nhắc tới.

**Cổng cố định (Catalog/Cart/order):** mỗi service chốt cổng của mình ngay trong `Program.cs` qua `app.Run("http://localhost:<port>")` (5001/5002/5003), kèm `Properties/launchSettings.json` khai báo `applicationUrl` cùng cổng để `dotnet run` khởi động đúng chỗ. `/health` trả shape cố định `{ service, status }` qua `Results.Json(...)` inline, tên service hardcode trong handler. (payment CHƯA đổi ở milestone này — vẫn `SERVICE_NAME` env + record `HealthResponse` + launchSettings 5004.) Ghi chú: `Config.cs`/`HealthResponse.cs` của Catalog/Cart/order còn nằm trong project nhưng `Program.cs` không còn tham chiếu — dead code, dọn được nếu muốn.

## Luật ranh giới (bất khả xâm phạm)

1. **Không tạo project "logic dùng chung".** Không `Shared`, `Common`, `Core`, `Libs` chứa business logic. Nếu hai service cần cùng một khái niệm, mỗi service tự định nghĩa phiên bản của mình. Ví dụ đang áp dụng: `HealthResponse` (record cho `GET /health`) — **4 file riêng** `services/<tên>/HealthResponse.cs`, nội dung giống nhau nhưng không project nào tham chiếu project khác. Khi cám dỗ "gom cho gọn", nhớ: đây chính là lằn ranh rule này bảo vệ.
2. **Service không `ProjectReference` sang service khác.** Không có tham chiếu project nào từ `services/A` sang `services/B`. Giao tiếp giữa service (khi milestone sau cần) đi qua HTTP API, không qua reference.
3. **Mỗi service build và chạy độc lập.** `dotnet build services/<tên>/<tên>.csproj` phải thành công mà không cần build service nào khác trước.
4. **Mỗi service sở hữu dữ liệu của nó.** Không đọc/ghi chéo dữ liệu. Chi tiết trách nhiệm từng service: [README.md](README.md).
5. **Thêm service mới = thêm thư mục `services/<tên>` VÀ `dotnet sln add` project đó vào `starci-shop.slnx`.** Solution bỏ sót một project vẫn build được các project còn lại nhưng service đó thành mồ côi — luôn kiểm tra bằng `dotnet sln list` sau khi thêm.

## Lệnh thường dùng

```bash
dotnet build                                  # build cả 4 service từ gốc
bash scripts/dev.sh                           # LỆNH GỐC: dựng Catalog+Cart+order cùng lúc (5001/5002/5003)
dotnet script scripts/health.csx              # probe /health cả đội — OK/ERR mỗi service, exit≠0 nếu có cái down
dotnet run --project services/Catalog         # chạy 1 service (cổng cứng 5001 trong app.Run)
dotnet sln list                               # xác nhận đủ 4 project được khai báo
```

Chạy dotnet ở **gốc repo** khi build/thao tác solution. Catalog/Cart/order chốt cổng trong `app.Run(...)` (5001/5002/5003) kèm `launchSettings.json` cùng cổng; payment vẫn theo `launchSettings.json` (5004). `bash scripts/dev.sh` là lệnh gốc dựng cả ba; `dotnet script scripts/health.csx` là probe (cần `dotnet tool install -g dotnet-script`). **Windows:** trap của dev.sh (`kill ${pids[*]}`) chỉ hạ subshell, tiến trình `dotnet` cháu bị mồ côi vẫn giữ cổng — dọn bằng `taskkill //F //PID <pid>` (tìm qua `netstat -ano | grep :5001`).

**Cảnh báo Windows (NTFS case-insensitive):** đổi tên chỉ khác hoa/thường (vd. `catalog` → `Catalog`) phải qua bước trung gian: `mv catalog __tmp && mv __tmp Catalog` — `mv catalog Catalog` trực tiếp báo lỗi "move vào chính nó". Sau khi đổi tên project, nếu `dotnet build` vẫn in ra path/AssemblyName casing cũ, đó là MSBuild build-server (node reuse) cache stale — chạy `dotnet build-server shutdown`, xoá `bin/`/`obj/`, rồi build lại.

## Quy ước khi sửa code

- Chưa chốt thư viện gì thêm ngoài ASP.NET Core minimal API có sẵn — đừng tự ý thêm EF Core, MediatR, AutoMapper... nếu task không yêu cầu.
- NuGet package mới khai báo trong `.csproj` **của service dùng nó**, không khai ở solution hay project khác.
- Sửa xong phải chứng minh: `dotnet build` (hoặc build riêng service bị sửa) thành công + `dotnet sln list` vẫn đủ 4 project. Với thay đổi runtime behavior (endpoint, config), chạy thật service (`dotnet run`) và gọi endpoint bằng `curl` — build/typecheck không xác nhận được hành vi lúc chạy.
- Cập nhật `README.md` khi (và chỉ khi) ranh giới trách nhiệm thay đổi — đó là quyết định lớn, nêu rõ với người dùng trước khi làm.
