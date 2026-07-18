# StarCi Shop — Hướng dẫn cho AI agent

Monorepo .NET chứa **bốn microservice độc lập**: Catalog, Cart, order, payment. Đây là bộ khung cho các milestone sau (container, database, gateway, saga, flash sale) — mọi thay đổi phải cắm vào khung này, không phá nó.

## Bố cục

```
starci-shop.slnx        # solution gốc — GỌI TÊN cả 4 service + Shop.Contracts, không dùng glob
README.md               # bản đồ service — ĐỌC TRƯỚC khi sửa bất kỳ service nào
packages/
  Shop.Contracts/        # contract dùng chung: CHỈ record/enum thuần (Money, ProductId, OrderStatus), KHÔNG logic
Dockerfile / .dockerignore  # đóng gói Catalog (đơn tầng, context=gốc) — milestone container
scripts/                 # dev.sh (dựng Catalog+Cart+order cùng lúc), health.csx (probe /health)
services/
  Catalog/               # sản phẩm         (:5001 mặc định — đọc PORT/SERVICE_NAME/CATALOG_DATABASE_URL từ env, Dockerized)
  Cart/                  # giỏ hàng         (http://localhost:5002, cổng cứng qua app.Run + launchSettings)
  order/                 # đơn hàng         (http://localhost:5003, cổng cứng qua app.Run + launchSettings)
  payment/               # thanh toán       (http://localhost:5004, launchSettings — chưa đổi milestone này)
```

Mỗi service: một `.csproj` (`Microsoft.NET.Sdk.Web`, `net10.0`) + `Program.cs` riêng. ASP.NET Core minimal API. **Cart/order/payment có `Properties/launchSettings.json`** khai báo `applicationUrl` cổng cố định (Cart 5002, order 5003, payment 5004). **Catalog KHÔNG có launchSettings** — cổng do env `PORT` điều khiển (mặc định 5001), để chạy được trong container.

**Casing có chủ đích:** `Catalog`/`Cart` dùng PascalCase (thư mục, `.csproj`, namespace đều khớp `Catalog`/`Cart`) vì đã có `Config.cs` với `namespace Catalog;` / `namespace Cart;`. `order`/`payment` chưa được nâng cấp lên pattern này — đừng tự ý đổi tên chúng khi không có yêu cầu, và đừng "sửa cho đồng bộ" nếu task không nhắc tới.

**Cổng — hai kiểu (chủ ý, do milestone khác nhau):**
- **Cart/order** (milestone dev-scripts): chốt cổng qua `app.Run("http://localhost:<port>")` (5002/5003) + launchSettings; `/health` inline `Results.Json({service,status})`. `Config.cs`/`HealthResponse.cs` của chúng là **dead code**.
- **Catalog** (milestone container): **env-driven** — đọc `PORT`/`SERVICE_NAME`/`CATALOG_DATABASE_URL` qua `Config.Load`, `builder.WebHost.UseUrls("http://0.0.0.0:{PORT}")` (bind mọi interface để reachable trong container), `/health` qua record `HealthResponse`, `/products` shape `{items,total}`. Nên `Config.cs`/`HealthResponse.cs` của Catalog LÀ **code sống**. Xem mục Docker trong `README.md`.
- **payment** (chưa đổi): `SERVICE_NAME` env + record `HealthResponse` + launchSettings 5004.

## Luật ranh giới (bất khả xâm phạm)

1. **Không chia sẻ business logic; CHỈ chia sẻ contract dữ liệu thuần.** Không `Shared`, `Common`, `Core`, `Libs` chứa business logic (controller, DbContext, HttpClient, quy tắc nghiệp vụ). Ngoại lệ DUY NHẤT là `packages/Shop.Contracts` — một class library (`Microsoft.NET.Sdk`) chứa **chỉ record/enum thuần** cho các kiểu dữ liệu phải khớp nhau qua ranh giới service (`Money`, `ProductId`, `OrderStatus`). Đây là single source of truth: một sửa trong contracts làm vỡ build ở MỌI consumer dùng sai — đó là điều ta muốn. Value type domain xuyên service → `Shop.Contracts`; DTO cục bộ của từng service thì KHÔNG — ví dụ `HealthResponse` (record cho `GET /health`) vẫn là **4 file riêng** `services/<tên>/HealthResponse.cs`, vì shape liveness là việc nội bộ mỗi service, không phải contract chung. Đừng nhét logic hay DTO nội bộ vào `Shop.Contracts`.
2. **Service không `ProjectReference` sang service KHÁC — nhưng ĐƯỢC tham chiếu `Shop.Contracts`.** Không có tham chiếu project nào từ `services/A` sang `services/B`; giao tiếp giữa service (khi milestone sau cần) đi qua HTTP API, không qua reference. Tham chiếu `packages/Shop.Contracts` là hợp lệ và là cách duy nhất để dùng chung kiểu contract.
3. **Mỗi service build và chạy độc lập.** `dotnet build services/<tên>/<tên>.csproj` phải thành công mà không cần service NÀO KHÁC — nó chỉ kéo theo `Shop.Contracts` (thư viện, không phải service) như một dependency.
4. **Mỗi service sở hữu dữ liệu của nó.** Không đọc/ghi chéo dữ liệu. Chi tiết trách nhiệm từng service: [README.md](README.md).
5. **Thêm service mới = thêm thư mục `services/<tên>` VÀ `dotnet sln add` project đó vào `starci-shop.slnx`.** Solution bỏ sót một project vẫn build được các project còn lại nhưng service đó thành mồ côi — luôn kiểm tra bằng `dotnet sln list` sau khi thêm.

## Lệnh thường dùng

```bash
dotnet build                                  # build cả 4 service + Shop.Contracts từ gốc
bash scripts/dev.sh                           # LỆNH GỐC: dựng Catalog+Cart+order cùng lúc (5001/5002/5003)
dotnet script scripts/health.csx              # probe /health cả đội — OK/ERR mỗi service, exit≠0 nếu có cái down
dotnet build services/Catalog                 # build 1 service độc lập (chỉ kéo theo Shop.Contracts)
dotnet run --project services/Catalog         # chạy Catalog (đọc PORT env, mặc định 5001)
dotnet sln list                               # xác nhận đủ 5 project (4 service + Shop.Contracts)
docker build -t starci-shop/catalog:dev .     # đóng gói Catalog (Dockerfile ở GỐC; context=gốc vì cần Shop.Contracts)
docker run -d -p 3001:3001 -e PORT=3001 -e CATALOG_DATABASE_URL=... starci-shop/catalog:dev  # cổng+DB từ env
```

Chạy dotnet ở **gốc repo** khi build/thao tác solution. Cart/order chốt cổng trong `app.Run(...)` (5002/5003) + launchSettings; **Catalog đọc `PORT` từ env** (mặc định 5001, bind `0.0.0.0`, Dockerized); payment theo `launchSettings.json` (5004). `bash scripts/dev.sh` là lệnh gốc dựng cả ba; `dotnet script scripts/health.csx` là probe (cần `dotnet tool install -g dotnet-script`). **Windows:** trap của dev.sh (`kill ${pids[*]}`) chỉ hạ subshell, tiến trình `dotnet` cháu bị mồ côi vẫn giữ cổng — dọn bằng `taskkill //F //PID <pid>` (tìm qua `netstat -ano | grep :5001`).

**Cảnh báo Windows (NTFS case-insensitive):** đổi tên chỉ khác hoa/thường (vd. `catalog` → `Catalog`) phải qua bước trung gian: `mv catalog __tmp && mv __tmp Catalog` — `mv catalog Catalog` trực tiếp báo lỗi "move vào chính nó". Sau khi đổi tên project, nếu `dotnet build` vẫn in ra path/AssemblyName casing cũ, đó là MSBuild build-server (node reuse) cache stale — chạy `dotnet build-server shutdown`, xoá `bin/`/`obj/`, rồi build lại.

## Quy ước khi sửa code

- Chưa chốt thư viện gì thêm ngoài ASP.NET Core minimal API có sẵn — đừng tự ý thêm EF Core, MediatR, AutoMapper... nếu task không yêu cầu.
- NuGet package mới khai báo trong `.csproj` **của service dùng nó**, không khai ở solution hay project khác.
- Kiểu dùng chung xuyên service (value type domain) đặt trong `packages/Shop.Contracts` và service tham chiếu qua `<ProjectReference>` — KHÔNG copy-paste một bản riêng vào service (làm vậy là quay lại drift mà library này xoá bỏ). `Shop.Contracts` chỉ chứa record/enum thuần.
- Sửa xong phải chứng minh: `dotnet build` (hoặc build riêng service bị sửa) thành công + `dotnet sln list` vẫn đủ 5 project (4 service + Shop.Contracts). Với thay đổi runtime behavior (endpoint, config), chạy thật service (`dotnet run`) và gọi endpoint bằng `curl` — build/typecheck không xác nhận được hành vi lúc chạy.
- Cập nhật `README.md` khi (và chỉ khi) ranh giới trách nhiệm thay đổi — đó là quyết định lớn, nêu rõ với người dùng trước khi làm.
