# StarCi Shop — Hướng dẫn cho AI agent

Monorepo .NET chứa **bốn microservice độc lập**: Catalog, Cart, order, payment. Đây là bộ khung cho các milestone sau (container, database, gateway, saga, flash sale) — mọi thay đổi phải cắm vào khung này, không phá nó.

## Bố cục

```
starci-shop.slnx        # solution gốc — GỌI TÊN cả 4 service + Shop.Contracts, không dùng glob
README.md               # bản đồ service — ĐỌC TRƯỚC khi sửa bất kỳ service nào
packages/
  Shop.Contracts/        # contract dùng chung: CHỈ record/enum thuần (Money, ProductId, OrderStatus), KHÔNG logic
Dockerfile              # đóng gói Catalog — ĐA TẦNG (sdk build → aspnet runtime, USER app), context=gốc
Dockerfile.single       # bản đơn tầng cũ, GIỮ LẠI chỉ để so kích thước (SDK lên tận production)
.dockerignore           # giữ build context gọn (bin/obj/.git/*.log/scripts/.env)
docker-compose.yaml     # CẢ SHOP 1 lệnh: db(postgres:16-alpine) + catalog:3001 + cart:3002 + order:3003
.env / .env.example     # secret Postgres cho compose — .env GITIGNORED, .env.example là mẫu commit được
scripts/                 # dev.sh (dựng Catalog+Cart+order cùng lúc), health.csx (probe /health)
services/
  Catalog/               # sản phẩm         (:5001 mặc định — PORT/SERVICE_NAME/DATABASE_URL từ env, Dockerized, /products đọc Postgres)
  Cart/                  # giỏ hàng         (:5002 mặc định — PORT/SERVICE_NAME/CATALOG_URL từ env, Dockerized)
  order/                 # đơn hàng         (:5003 mặc định — PORT/SERVICE_NAME/CATALOG_URL/CART_URL/DATABASE_URL từ env, Dockerized, /health ping DB thật + HEALTHCHECK)
  payment/               # thanh toán       (http://localhost:5004, launchSettings — chưa đổi milestone này)
```

Mỗi service: một `.csproj` (`Microsoft.NET.Sdk.Web`, `net10.0`) + `Program.cs` riêng. ASP.NET Core minimal API. **Cart/order/payment có `Properties/launchSettings.json`** khai báo `applicationUrl` cổng cố định (Cart 5002, order 5003, payment 5004). **Catalog KHÔNG có launchSettings** — cổng do env `PORT` điều khiển (mặc định 5001), để chạy được trong container.

**Casing có chủ đích:** `Catalog`/`Cart` dùng PascalCase (thư mục, `.csproj`, namespace đều khớp `Catalog`/`Cart`) vì đã có `Config.cs` với `namespace Catalog;` / `namespace Cart;`. `order`/`payment` chưa được nâng cấp lên pattern này — đừng tự ý đổi tên chúng khi không có yêu cầu, và đừng "sửa cho đồng bộ" nếu task không nhắc tới.

**Cổng — env-driven cho 3 service trong compose, payment chưa đổi:**
- **Catalog/Cart/order** (milestone compose): **đọc `PORT` từ env** (mặc định 5001/5002/5003) và `builder.WebHost.UseUrls("http://0.0.0.0:{PORT}")` — bind mọi interface để container reachable qua `-p`. Không `app.Run("http://localhost:...")` nữa. `launchSettings.json` của Cart/order vẫn giữ (dev tiện), nhưng cổng thật do `PORT` quyết định. `Config.cs` của Catalog/Cart LÀ **code sống**; order đọc env inline trong `Program.cs` (chưa nâng lên pattern `Config.cs` — đừng "sửa cho đồng bộ" nếu task không nhắc).
- **Địa chỉ phụ thuộc luôn từ env, không hardcode host service khác:** Catalog `DATABASE_URL` (hoặc `CATALOG_DATABASE_URL` — ưu tiên cao hơn), Cart `CATALOG_URL`, order `CATALOG_URL`+`CART_URL`. Trong compose các giá trị này là **DNS theo tên service** (`db`, `catalog`, `cart`), ngoài compose default về localhost.
- **payment** (chưa đổi): `SERVICE_NAME` env + record `HealthResponse` + launchSettings 5004, cổng chưa env-driven, chưa có Dockerfile.
- **`scripts/health.csx` probe `127.0.0.1`, KHÔNG `localhost`** — service bind `0.0.0.0` (IPv4) còn `localhost` trên Windows phân giải `::1` trước → HttpClient treo tới timeout dù service vẫn sống.

**`/health` của order là READINESS thật, ba service kia là liveness** (milestone healthcheck): order chạy `SELECT 1` tới Postgres mỗi lần được gọi (`services/order/DatabaseProbe.cs`) → DB sống trả `200 {"service":"order","status":"ok"}`, DB chết trả **`503 {"service":"order","status":"unhealthy","error":...}`**. `services/order/Dockerfile` có `HEALTHCHECK` (dạng **shell** để `${PORT:-3003}` nở lúc chạy) dùng `curl -fsS` thăm dò chính endpoint đó, nên `docker compose ps` chỉ báo order `(healthy)` khi nó thật sự nối được DB. **ĐỪNG đổi handler này về `ok` cứng** — đó là toàn bộ điểm của milestone; một 200 giả làm orchestrator đẩy checkout vào service không có DB. Hệ quả cần biết: chạy `bash scripts/dev.sh` **không có Postgres** thì `health.csx` báo **ERR cho order** — hành vi đúng, không phải hồi quy; muốn xanh thì `docker compose up -d db` trước hoặc trỏ `ORDER_DATABASE_URL`. `curl` là thứ duy nhất cài thêm vào tầng runtime của order (trước `USER app`, vì apt cần root).

**Catalog và Postgres:** `/products` đọc bảng `products` trong Postgres qua `Npgsql` (ADO thuần, **không** EF Core) — xem `services/Catalog/ProductStore.cs`. Seed chỉ chạy khi bảng còn rỗng, nên dữ liệu sống qua `docker compose down && up` (named volume `pgdata`). Không có DB (chạy `bash scripts/dev.sh` ngoài Docker) thì store retry 5 lần rồi **fallback seed in-memory** để service vẫn boot — log ghi rõ `products source = postgres | in-memory seed`. Npgsql là NuGet duy nhất được thêm, và chỉ trong `Catalog.csproj`.

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
docker build -t starci-shop/catalog:slim .    # đóng gói Catalog ĐA TẦNG (Dockerfile ở GỐC; context=gốc vì cần Shop.Contracts)
docker build -f Dockerfile.single -t catalog:single .  # bản đơn tầng cũ — chỉ để so kích thước
docker run -d -p 3001:3001 -e PORT=3001 -e CATALOG_DATABASE_URL=... starci-shop/catalog:slim  # cổng+DB từ env

cp .env.example .env                          # BẮT BUỘC trước lần compose đầu (secret Postgres, .env gitignored)
docker compose up --build -d                  # CẢ SHOP 1 lệnh: db + catalog:3001 + cart:3002 + order:3003
docker compose ps                             # db "healthy" TRƯỚC, order "Up (healthy)" (HEALTHCHECK trong image)
curl -s localhost:3003/health                 # {"service":"order","status":"ok"} — chạy SELECT 1 tới Postgres
docker compose stop db && curl -s -o /dev/null -w '%{http_code}' localhost:3003/health  # 503, không phải 200 giả
docker compose exec catalog getent hosts db   # DNS theo tên service (172.x db) — không localhost, không IP cứng
docker compose down                           # KHÔNG dùng `down -v`: -v xoá volume pgdata = mất dữ liệu seed
```

Chạy dotnet ở **gốc repo** khi build/thao tác solution. **Catalog/Cart/order đọc `PORT` từ env** (mặc định 5001/5002/5003, bind `0.0.0.0`, cả ba Dockerized và có mặt trong `docker-compose.yaml`); payment theo `launchSettings.json` (5004). `bash scripts/dev.sh` là lệnh gốc dựng cả ba; `dotnet script scripts/health.csx` là probe (cần `dotnet tool install -g dotnet-script`). **Windows:** trap của dev.sh (`kill ${pids[*]}`) chỉ hạ subshell, tiến trình `dotnet` cháu bị mồ côi vẫn giữ cổng — dọn bằng `taskkill //F //PID <pid>` (tìm qua `netstat -ano | grep :5001`).

**Cảnh báo Windows (NTFS case-insensitive):** đổi tên chỉ khác hoa/thường (vd. `catalog` → `Catalog`) phải qua bước trung gian: `mv catalog __tmp && mv __tmp Catalog` — `mv catalog Catalog` trực tiếp báo lỗi "move vào chính nó". Sau khi đổi tên project, nếu `dotnet build` vẫn in ra path/AssemblyName casing cũ, đó là MSBuild build-server (node reuse) cache stale — chạy `dotnet build-server shutdown`, xoá `bin/`/`obj/`, rồi build lại.

## Quy ước khi sửa code

- Ngoài ASP.NET Core minimal API, thư viện duy nhất đã chốt là **`Npgsql`** — khai trong `Catalog.csproj` (đọc bảng `products`) và `order.csproj` (readiness probe `SELECT 1`), **cùng version `10.0.3`**, ADO thuần. Đừng tự ý thêm EF Core, Dapper, MediatR, AutoMapper... nếu task không yêu cầu — và nếu cần truy cập DB ở service khác thì khai `Npgsql` trong `.csproj` của **chính** service đó. Việc order **copy** hàm `ToConnectionString` thay vì tái dùng của Catalog là CỐ Ý: service không `ProjectReference` sang service khác, và đây là plumbing hạ tầng chứ không phải contract nên cũng không thuộc `Shop.Contracts`.
- NuGet package mới khai báo trong `.csproj` **của service dùng nó**, không khai ở solution hay project khác.
- Kiểu dùng chung xuyên service (value type domain) đặt trong `packages/Shop.Contracts` và service tham chiếu qua `<ProjectReference>` — KHÔNG copy-paste một bản riêng vào service (làm vậy là quay lại drift mà library này xoá bỏ). `Shop.Contracts` chỉ chứa record/enum thuần.
- Sửa xong phải chứng minh: `dotnet build` (hoặc build riêng service bị sửa) thành công + `dotnet sln list` vẫn đủ 5 project (4 service + Shop.Contracts). Với thay đổi runtime behavior (endpoint, config), chạy thật service (`dotnet run`) và gọi endpoint bằng `curl` — build/typecheck không xác nhận được hành vi lúc chạy.
- Cập nhật `README.md` khi (và chỉ khi) ranh giới trách nhiệm thay đổi — đó là quyết định lớn, nêu rõ với người dùng trước khi làm.
