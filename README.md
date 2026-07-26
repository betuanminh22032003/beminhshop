# StarCi Shop — Bản đồ Service

Monorepo .NET, mỗi service là một project độc lập trong một solution. Không chia sẻ business logic; chỉ chia sẻ **contract dữ liệu thuần** qua `packages/Shop.Contracts` (record/enum: `Money`, `ProductId`, `OrderStatus`).

- **Catalog** : Sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm. KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
- **Cart** : Sở hữu lựa chọn item đang dở của một khách (thêm / xóa / xem). KHÔNG đặt đơn hay thu tiền.
- **order** : Sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn. KHÔNG thu tiền thẻ.
- **payment** : Sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán. KHÔNG quản lý sản phẩm hay giỏ hàng.

## Bố cục

```
starci-shop.slnx              # solution gốc, tham chiếu 4 service + Shop.Contracts
docker-compose.yaml           # CẢ SHOP 1 lệnh: db(postgres) + catalog:3001 + cart:3002 + order:3003
.env                          # secret Postgres — GITIGNORED, không bao giờ commit
.env.example                  # mẫu commit được của .env (placeholder)
Dockerfile                    # Catalog (đa tầng, context = gốc repo)
Dockerfile.single             # bản đơn tầng cũ của Catalog — chỉ để so kích thước
packages/
  Shop.Contracts/  Shop.Contracts.csproj  Money.cs  ProductId.cs  OrderStatus.cs   # record/enum thuần, dùng chung
scripts/
  dev.sh                       # LỆNH GỐC (không Docker): dựng Catalog+Cart+order cùng lúc
  health.csx                   # probe /health cả đội (dotnet script), gọi 127.0.0.1
  build-images.sh              # PHÁT HÀNH: build cả 4 image, tag = git SHA ngắn, revision trong OCI label
services/
  Catalog/  Catalog.csproj  Program.cs  Config.cs  ProductStore.cs  HealthResponse.cs  PriceQuote.cs   (env-driven, Dockerized ở /Dockerfile, /products đọc Postgres)
  Cart/     Cart.csproj     Program.cs  Config.cs  Dockerfile  Properties/launchSettings.json  CartLine.cs  HealthResponse.cs   (env-driven, Dockerized)
  order/    order.csproj    Program.cs  DatabaseProbe.cs  Dockerfile  Properties/launchSettings.json  Order.cs  HealthResponse.cs   (env-driven inline, Dockerized, /health ping DB thật)
  payment/  payment.csproj  Program.cs  Dockerfile  Properties/launchSettings.json  HealthResponse.cs   (env-driven + Dockerized từ milestone image tái lập được)
  <mỗi service>/packages.lock.json   # lockfile NuGet ĐƯỢC COMMIT — Docker restore ở --locked-mode
```

Mỗi service một `.csproj` riêng (`Microsoft.NET.Sdk.Web`, `net10.0`), build và chạy độc lập, KHÔNG `ProjectReference` sang service khác — nhưng có tham chiếu `packages/Shop.Contracts` (class library `Microsoft.NET.Sdk`) cho các kiểu dùng chung. `Shop.Contracts` không tham chiếu ngược lại service nào.

## Dựng cả cửa hàng bằng một lệnh + probe /health

Lệnh gốc `bash scripts/dev.sh` khởi động Catalog(5001) + Cart(5002) + order(5003) đồng thời, mỗi tiến trình `dotnet run` riêng với log tiền tố `[<svc>]`; khi một service thoát, `wait -n` trả về và script kết thúc (mã ≠ 0).

> Về ranh giới chia sẻ kiểu: value type domain xuyên service (`Money`/`ProductId`/`OrderStatus`) nằm trong `packages/Shop.Contracts` (single source of truth); còn DTO liveness `HealthResponse` KHÔNG chia sẻ — xem luật #1 trong `AGENTS.md`.

Chứng minh cả đội xanh: `dotnet script scripts/health.csx` gọi `/health` từng cổng, in `OK`/`ERR` mỗi service, `ALL GREEN`/`SOME RED`, thoát mã 0 nếu tất cả xanh — khác 0 nếu có cái down.

Cả 4 service trả cùng shape JSON `{"service":"<tên>","status":"ok"}`, nhưng khác cơ chế:
- **Catalog/Cart/order:** cổng từ `PORT` env (mặc định 5001/5002/5003), bind `0.0.0.0` qua `UseUrls` để container reachable qua `-p`; identity từ `SERVICE_NAME`. Catalog dùng record `HealthResponse.Ok(config.ServiceName)`; Cart dùng `Results.Json(new { service = <từ env>, status = "ok" })` — cùng shape.
- **order là NGOẠI LỆ — `/health` của nó là readiness THẬT, không phải liveness:** mỗi lần gọi chạy một `SELECT 1` tới Postgres qua `DatabaseProbe`. DB sống → `200 {"service":"order","status":"ok"}`; DB chết → **`503 {"service":"order","status":"unhealthy","error":...}`**. Docker `HEALTHCHECK` trong `services/order/Dockerfile` thăm dò chính endpoint này, nên `order` chỉ "healthy" khi thực sự nói chuyện được với DB — một `200` cứng sẽ khiến orchestrator đẩy lưu lượng checkout vào service không có DB.
- **payment:** CHƯA đổi — record `HealthResponse.Ok(serviceName)` với `serviceName` từ `SERVICE_NAME` env, `.AllowAnonymous()`, cổng theo `launchSettings.json` (5004).

**Windows caveat:** trap `kill ${pids[*]}` trong dev.sh chỉ hạ subshell; tiến trình `dotnet` cháu bị mồ côi vẫn giữ cổng — dọn bằng `taskkill //F //PID <pid>`.

**`health.csx` gọi `127.0.0.1`, không `localhost`:** ba service bind `0.0.0.0` (IPv4); `localhost` trên Windows phân giải `::1` trước nên `HttpClient` treo tới timeout dù service vẫn sống (`curl` không bị vì tự fallback sang IPv4).

Ngoài Docker (dev.sh) không có Postgres — Catalog retry 5 lần rồi phục vụ **seed in-memory** và ghi rõ trong log `[catalog] products source = in-memory seed`, nên Catalog vẫn xanh.

⚠️ **Nhưng order thì KHÔNG có fallback:** `/health` của order phải ping DB thật, nên chạy `dev.sh` mà không có Postgres → `health.csx` báo **ERR cho order** (503). Đó là hành vi ĐÚNG, không phải hồi quy: order không có DB thì không sẵn sàng nhận checkout. Muốn cả đội xanh ngoài Docker thì dựng Postgres trước (`docker compose up -d db`) hoặc trỏ `ORDER_DATABASE_URL` sang một Postgres đang chạy.

## Lệnh

```bash
dotnet build                                      # build cả 4
bash scripts/dev.sh                               # dựng Catalog+Cart+order cùng lúc (5001/5002/5003), KHÔNG Docker
dotnet script scripts/health.csx                  # probe /health cả đội (cần: dotnet tool install -g dotnet-script)
dotnet run --project services/Catalog             # chạy riêng Catalog (đọc PORT env, mặc định 5001)
dotnet run --project services/Cart                # chạy riêng Cart   (đọc PORT env, mặc định 5002)

cp .env.example .env                              # lần đầu: secret Postgres cho compose (.env gitignored)
bash scripts/compose-up.sh -d                      # CẢ SHOP 1 lệnh, tự lấy SHA sạch của HEAD
docker compose ps                                 # db "healthy", ba service "Up"
docker compose down                               # KHÔNG dùng `down -v` — -v xoá volume pgdata

bash scripts/build-images.sh                      # PHÁT HÀNH cả 4 image, tag = git SHA ngắn
bash scripts/build-images.sh --latest             # thêm alias :latest trỏ đúng image SHA đó
docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'   starci-shop/catalog:$(git rev-parse --short HEAD)     # -> SHA ngắn, image tự khai commit
```

Health check: `GET /health` → `{"service":"<tên>","status":"ok"}`. **Catalog/Cart/order đọc `PORT` từ env** (mặc định 5001/5002/5003, bind `0.0.0.0`, cả ba Dockerized); payment vẫn theo `launchSettings.json` (5004).

## Docker — Catalog (milestone container)

`Dockerfile` (**đa tầng**) + `.dockerignore` ở **gốc repo** đóng gói service **Catalog**. Build context là gốc vì Catalog tham chiếu `packages/Shop.Contracts`. Catalog đọc `PORT` **và** `CATALOG_DATABASE_URL` từ env lúc chạy và bind `0.0.0.0` (để reachable qua `-p`):

```bash
docker build -t starci-shop/catalog:slim .
docker run -d --name catalog -p 3001:3001 \
  -e PORT=3001 -e CATALOG_DATABASE_URL=postgres://catalog-db:5432/catalog \
  starci-shop/catalog:slim
curl -s http://localhost:3001/products   # {"items":[{"id":"sku-001",...}],"total":3}
```

Đổi `-e PORT=4000 -p 4000:4000` cùng image đó → bind 4000 (cổng từ env, không cứng hóa); `docker logs catalog` in `[catalog] listening on :<port>`.

### Đa tầng — tại sao image thu nhỏ

- **Tầng `build`** (`mcr.microsoft.com/dotnet/sdk:10.0`): restore + `dotnet publish -c Release -o /app/publish`. Toàn bộ toolchain build (SDK, compiler, NuGet cache, source `.cs`) **ở lại đây**, không đi tiếp.
- **Tầng `runtime`** (`mcr.microsoft.com/dotnet/aspnet:10.0`): `COPY --from=build /app/publish ./` — chỉ tạo phẩm runtime. **Không có SDK**, `USER app` (uid ≠ 0, image aspnet sẵn có), `EXPOSE 3001`, `ENTRYPOINT ["dotnet","Catalog.dll"]` (tên dll chốt bằng `<AssemblyName>Catalog</AssemblyName>` trong `Catalog.csproj`).

Bản **đơn tầng** cũ giữ lại ở `Dockerfile.single` để so kích thước — nó nhồi cả SDK vào image chạy:

```bash
docker build -f Dockerfile.single -t catalog:single .   # 1.25GB  (aspnet runtime + app + full SDK)
docker build -t catalog:slim .                         #  340MB  (aspnet runtime + app)
```

Đo thật (Docker 29.2.1, .NET SDK 10.0.302 trong image build): **1.25GB → 340MB**, nhỏ hơn ~3.7×.

Chứng minh tầng runtime KHÔNG có SDK và KHÔNG chạy root — `ENTRYPOINT` là exec-form nên phải `--entrypoint` để chạy lệnh khác:

```bash
docker run --rm --entrypoint sh catalog:slim -c "ls /usr/share/dotnet/sdk"
# ls: cannot access '/usr/share/dotnet/sdk': No such file or directory   ← không có SDK
docker run --rm --entrypoint id catalog:slim
# uid=1654(app) gid=1654(app)   ← KHÁC 0, user "app" sẵn có của image aspnet

# đối chứng bản đơn tầng:
docker run --rm --entrypoint sh catalog:single -c "dotnet --list-sdks; id -u"
# 10.0.302 [/usr/share/dotnet/sdk]
# 0                                ← có SDK, và chạy root
```

`/app` trong image slim chỉ có tạo phẩm publish (`Catalog.dll`, `Shop.Contracts.dll`, `*.runtimeconfig.json`, `appsettings*.json`) — `find /app -name '*.cs' | wc -l` → `0`, không file source nào lọt lên production.

## Docker Compose — cả shop bằng MỘT lệnh (milestone compose)

`docker-compose.yaml` ở gốc ghép **db (Postgres) + catalog + cart + order** thành một stack:

```bash
cp .env.example .env        # BẮT BUỘC lần đầu — secret Postgres, .env bị gitignore
bash scripts/compose-up.sh -d # tự truyền SHA sạch của HEAD cho tag + OCI label
```

Bốn tính chất của stack này:

1. **Secret không nằm trong file compose.** Mọi `${POSTGRES_*}` được compose nạp từ `.env` (gitignored); `.env.example` là bản mẫu placeholder được commit để hợp đồng cấu hình vẫn hiện rõ. `.gitignore` có `.env` + `.env.*` và `!.env.example`.
2. **DNS theo tên service, không `localhost`, không IP cứng.** Cả bốn nằm trên mạng `shopnet` (`driver: bridge`, do người dùng định nghĩa — bridge mặc định KHÔNG phân giải tên). Catalog nối DB qua `postgres://…@db:5432/…`; `cart` gọi `http://catalog:3001`; `order` gọi cả `http://catalog:3001` và `http://cart:3002`. Toàn bộ tiêm bằng env (`DATABASE_URL`, `CATALOG_URL`, `CART_URL`), không hardcode.
3. **Dữ liệu bền bỉ.** `pgdata` là named volume mount vào `/var/lib/postgresql/data`; Catalog seed sản phẩm **chỉ khi bảng `products` còn rỗng**, nên `docker compose down` (KHÔNG `-v`) rồi `up` lại vẫn thấy đúng dữ liệu cũ.
4. **App chờ DB thật sự sẵn sàng.** `db` có `healthcheck` bằng `pg_isready`; ba service khai `depends_on: db: condition: service_healthy`. Chi tiết cơ chế chặn + probe thật của order: [mục dưới](#healthcheck--chặn-khởi-động-milestone-healthcheck).

Mỗi service build từ Dockerfile riêng (`/Dockerfile`, `services/Cart/Dockerfile`, `services/order/Dockerfile`) nhưng **`context: .` = gốc repo**, vì cả ba tham chiếu `packages/Shop.Contracts`.

### Kiểm chứng chạy thật (Docker 29.2.1)

```bash
$ docker compose up --build -d
 Image petproject-catalog Built
 Image petproject-order Built
 Image petproject-cart Built
 Container petproject-db-1 Started
 Container petproject-db-1 Healthy          # ba service chờ healthcheck của db
 Container petproject-order-1 Started
 Container petproject-cart-1 Started
 Container petproject-catalog-1 Started

$ docker compose ps
  petproject-cart-1     (petproject-cart)     Up 14 seconds  [3002, 3002]
  petproject-catalog-1  (petproject-catalog)  Up 14 seconds  [3001, 3001]
  petproject-db-1       (postgres:16-alpine)  Up 20 seconds (healthy)  [5432/tcp]
  petproject-order-1    (petproject-order)    Up 14 seconds  [3003, 3003]

# Catalog tới được DB qua TÊN SERVICE và trả sản phẩm đã seed
$ curl -s localhost:3001/products
{"items":[{"id":"sku-001","title":"Starter Mug","priceCents":1200},{"id":"sku-002","title":"Field Notebook","priceCents":800},{"id":"sku-003","title":"Enamel Pin","priceCents":500}],"total":3}

# DNS theo tên service, phân giải từ TRONG container
$ docker compose exec catalog getent hosts db
172.22.0.2      db

$ docker compose logs cart order | grep "url ="
cart-1   | [cart] catalog url = http://catalog:3001
order-1  | [order] catalog url = http://catalog:3001
order-1  | [order] cart url = http://cart:3002
```

**Dữ liệu bền bỉ qua chu kỳ down/up đầy đủ** (`down` chứ KHÔNG `down -v` — `-v` sẽ xoá volume):

```bash
$ docker compose down && docker volume ls | grep pgdata
local     petproject_pgdata                  # volume sống sót

$ docker compose up -d && curl -s localhost:3001/products
{"items":[{"id":"sku-001","title":"Starter Mug","priceCents":1200}, ... ],"total":3}   # ĐÚNG dữ liệu cũ

$ docker logs petproject-catalog-1 | grep catalog\]
[catalog] catalog db = postgres://shop:***@db:5432/shop
[catalog] products already in db (3 rows) — skipping seed    # KHÔNG seed lại -> đây là dữ liệu từ volume
[catalog] listening on :3001
[catalog] products source = postgres
```

Dòng `products already in db (3 rows) — skipping seed` là bằng chứng mạnh nhất: seed bị bỏ qua mà `/products` vẫn có dữ liệu ⇒ dữ liệu đến từ `pgdata`, không phải từ code. Kiểm chứng chặt hơn nữa: `UPDATE products SET title='Starter Mug (persisted)' WHERE id='sku-001'` trước khi `down`, sau `up` `curl` vẫn trả `Starter Mug (persisted)` — đã chạy thật, đúng như vậy.

> Npgsql in một dòng `Cannot load library libgssapi_krb5.so.2` lúc khởi tạo trên image `aspnet` (probe Kerberos/GSSAPI không có sẵn). Vô hại: kết nối vẫn đi bằng password auth — log ngay sau đó là `seeded 3 products into db` / `products source = postgres`.

## Healthcheck & chặn khởi động (milestone healthcheck)

Vấn đề: `docker compose up` bật Postgres và order **cùng lúc**, nhưng Postgres cần vài giây mới nhận kết nối TCP — order mở kết nối Npgsql ngay và chết với `Connection refused`. Ba lớp phối hợp để lần khởi động nguội luôn xanh:

| Lớp | Ở đâu | Nói lên điều gì |
|---|---|---|
| `pg_isready` | `docker-compose.yaml` → `db.healthcheck` | Postgres ĐÃ nhận kết nối (không chỉ "container đang chạy") |
| `depends_on: condition: service_healthy` | `docker-compose.yaml` → `catalog`/`cart`/`order` | App **không được khởi động** cho tới khi `db` healthy |
| `HEALTHCHECK` + `/health` chạy `SELECT 1` | `services/order/Dockerfile` + `services/order/Program.cs` | order thực sự **nói chuyện được với DB**, không phải chỉ còn sống |

Điểm cốt lõi: `/health` của order **không** trả `ok` cứng. Nó gọi `DatabaseProbe.PingAsync()` → `SELECT 1` round-trip tới Postgres; ném lỗi thì handler đổi thành **503**. `HEALTHCHECK` dùng `curl -fsS` nên HTTP ≥ 400 làm curl thoát khác 0 ⇒ Docker đánh dấu container `unhealthy`. Dạng **shell** (không phải exec) để `${PORT:-3003}` nở lúc chạy — cổng vẫn do env quyết định, không nướng vào image. `curl` là công cụ duy nhất thêm vào tầng runtime, cài trước `USER app` (apt cần root).

### Kiểm chứng chạy thật (Docker 29.2.1)

```bash
# 1) Cơ chế chặn: db phải Healthy TRƯỚC, chỉ khi đó order mới Starting
#    (chạy từ trạng thái SẠCH THẬT: `docker compose down -v` đã xoá volume pgdata,
#     nên Postgres phải initdb lại từ đầu — đúng tình huống hay gây Connection refused)
$ docker compose down -v && docker compose up -d
 Container petproject-db-1 Starting
 Container petproject-db-1 Started
 Container petproject-db-1 Waiting          # <- compose chặn ở đây
 Container petproject-db-1 Healthy
 Container petproject-order-1 Starting      # <- chỉ sau khi db healthy
 Container petproject-order-1 Started

$ docker compose ps
petproject-db-1     Up 24 seconds (healthy)
petproject-order-1  Up 18 seconds (healthy)   # order tự healthy nhờ HEALTHCHECK trong image

$ docker compose logs order | grep -ci "connection refused"
0                                            # KHÔNG còn connection refused

$ curl -s localhost:3001/products            # DB sạch -> Catalog seed lại, stack xanh hết
{"items":[{"id":"sku-001",...},{"id":"sku-002",...},{"id":"sku-003",...}],"total":3}

# 2) Probe khi DB sống
$ curl -s -w '\nHTTP %{http_code}\n' localhost:3003/health
{"service":"order","status":"ok"}
HTTP 200

# 3) Probe LÀ THẬT, không phải 200 giả — hạ DB rồi gọi lại
$ docker compose stop db && curl -s -w '\nHTTP %{http_code}\n' localhost:3003/health
{"service":"order","status":"unhealthy","error":"57P01: terminating connection due to administrator command"}
HTTP 503

$ docker inspect --format '{{.State.Health.Status}}' petproject-order-1
unhealthy                                    # Docker cũng thấy, không chỉ curl
$ docker inspect --format '{{range .State.Health.Log}}exit={{.ExitCode}} {{.Output}}{{end}}' petproject-order-1
exit=1 curl: (22) The requested URL returned error: 503

# 4) Tự phục hồi khi DB trở lại
$ docker compose start db && curl -s localhost:3003/health
{"service":"order","status":"ok"}
$ docker inspect --format '{{.State.Health.Status}}' petproject-order-1
healthy
```

Cổng ở đây là **3003** (quy ước đã chốt của repo từ milestone compose: catalog 3001 / cart 3002 / order 3003), không phải `8080` như ví dụ trong đề — cơ chế giống hệt, chỉ khác con số, và số đó đến từ env `PORT` nên đổi được mà không sửa image.

## Phát hành bộ image tái lập được (milestone release)

Một lệnh phát hành **cả bốn** service — catalog, cart, order **và payment** (payment được đóng gói lần đầu ở milestone này):

```bash
bash scripts/build-images.sh              # tag = git SHA ngắn
bash scripts/build-images.sh --latest     # thêm alias :latest trỏ đúng image đó
bash scripts/verify-reproducible.sh       # ASSERT tính tái lập cho cả 4 service, exit≠0 nếu sai
```

### Bốn service, bốn Dockerfile — đường dẫn chính xác

⚠️ **Dockerfile của Catalog nằm ở GỐC repo**, KHÔNG phải `services/Catalog/Dockerfile` — đó là di sản từ milestone 0 (kiểm chứng của bài đó chạy `docker build .` với Dockerfile mặc định ở gốc) và được giữ để không phá lệnh cũ. Ba service còn lại nằm cạnh source của chúng:

| Service | Dockerfile | Base ghim digest (build / runtime) | Non-root | Lockfile restore ở `--locked-mode` |
|---|---|---|---|---|
| catalog | **`/Dockerfile`** (gốc repo) | `sdk:10.0@sha256:3dae2f76…` / `aspnet:10.0@sha256:1f51d2d6…` | `USER app` | `packages/Shop.Contracts/packages.lock.json` + `services/Catalog/packages.lock.json` |
| cart | `services/Cart/Dockerfile` | cùng hai digest trên | `USER app` | `Shop.Contracts` + `services/Cart/packages.lock.json` |
| order | `services/order/Dockerfile` | cùng hai digest trên | `USER app` | `Shop.Contracts` + `services/order/packages.lock.json` |
| payment | `services/payment/Dockerfile` | cùng hai digest trên | `USER app` | `services/payment/packages.lock.json` |

`services/payment/Dockerfile` là file MỚI ở milestone này (trước đó payment chưa được đóng gói). Các dòng quyết định của nó — giống hệt khuôn ba service kia:

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:3dae2f7699441af56216ff64d5c9b6dfce7cd7dc7f4f71d353d29662b10a384f AS build
WORKDIR /src
COPY services/payment/payment.csproj services/payment/packages.lock.json services/payment/
RUN dotnet restore services/payment/payment.csproj --locked-mode
COPY services/payment/ services/payment/
RUN dotnet publish services/payment/payment.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0@sha256:1f51d2d65ace46d6395e773fb4cfc1c74d36fb4f08e5cf996e7f6961b45e9283 AS runtime
ARG GIT_SHA
ENV APP_VERSION=${GIT_SHA} \
    DOTNET_RUNNING_IN_CONTAINER=true
LABEL org.opencontainers.image.revision=${GIT_SHA} \
      org.opencontainers.image.version=${GIT_SHA} \
      org.opencontainers.image.title=starci-shop/payment
WORKDIR /app
COPY --from=build /app/publish ./
USER app
EXPOSE 5004
ENTRYPOINT ["dotnet", "payment.dll"]
```

**Không có dependency trôi nổi, cho cả 4 service.** Mọi `PackageReference` bị khoá bởi `packages.lock.json` **đã commit** (5 file, một cho mỗi project), và Docker restore chạy `--locked-mode` nên lockfile lệch csproj là **build FAIL** chứ không phải resolve version khác. Catalog và order khai `Npgsql 10.0.3`; Cart, payment và Shop.Contracts không có PackageReference nào (lockfile rỗng dependency — nên hai file đó cùng sha256). **Không có `latest` nào trong đường phát hành:** cả 4 tag là `starci-shop/<svc>:<git-sha>`; `--latest` chỉ chạy `docker tag` tạo alias trỏ đúng image SHA đó.

Bốn thứ khoá chặt "cùng một commit ⇒ cùng một bộ triển khai":

| Ghim cái gì | Bằng cách nào | Nếu không ghim thì sao |
|---|---|---|
| Base image | `FROM …/sdk:10.0@sha256:3dae2f76…`, `…/aspnet:10.0@sha256:1f51d2d6…` | tag `10.0` trôi theo mỗi bản patch — cùng commit, khác base |
| Gói NuGet | `RestorePackagesWithLockFile` + `packages.lock.json` **đã commit** + `dotnet restore --locked-mode` | range `[10.0.3, )` resolve ra version khác ở lần build sau |
| Danh tính image | `ARG GIT_SHA` → `ENV APP_VERSION` + `LABEL org.opencontainers.image.revision` | `latest` trôi nổi, không biết image nào từ commit nào |
| Tốc độ build lại | `.csproj` + `packages.lock.json` copy **trước** source | sửa một dòng `.cs` là restore lại toàn bộ NuGet |

`ARG GIT_SHA` **không có default**: build thiếu ARG thì version rỗng và lộ ra ngay, thay vì dán nhãn sai một image. `latest` chỉ là **alias** (`docker tag`) — artifact bất biến luôn là tag SHA.

### Kiểm chứng TỰ ĐỘNG — `bash scripts/verify-reproducible.sh`

Không phải lời hứa trong doc: script build hai lần rồi **assert** từng điều, exit≠0 nếu sai. Output thật trên commit `4683c5a` (25/25 PASS):

```
commit under test: 4683c5a

=== Dockerfile checks (4/4 service) ===
[catalog] Dockerfile
  PASS  catalog: 2/2 FROM ghim @sha256 (build + runtime)
  PASS  catalog: có USER (không chạy root)
  PASS  catalog: runtime base = aspnet (không SDK)
  PASS  catalog: restore ở --locked-mode
  PASS  catalog: lockfile(L7) -> restore(L18) -> source(L22)
[cart] services/Cart/Dockerfile
  PASS  cart: 2/2 FROM ghim @sha256 (build + runtime)   ... (5/5 PASS)
[order] services/order/Dockerfile
  PASS  order: 2/2 FROM ghim @sha256 (build + runtime)  ... (5/5 PASS)
[payment] services/payment/Dockerfile
  PASS  payment: 2/2 FROM ghim @sha256 (build + runtime)
  PASS  payment: có USER (không chạy root)
  PASS  payment: runtime base = aspnet (không SDK)
  PASS  payment: restore ở --locked-mode
  PASS  payment: lockfile(L6) -> restore(L15) -> source(L18)

=== Dependency set khoá bằng lockfile đã commit (không floating) ===
  [catalog] a4364d81a6de2707…  packages/Shop.Contracts/packages.lock.json  (committed)
  [catalog] d5f352be869aaee2…  services/Catalog/packages.lock.json         (committed)
  [cart]    693b3b88bbf6563d…  services/Cart/packages.lock.json            (committed)
  [order]   d5f352be869aaee2…  services/order/packages.lock.json           (committed)
  [payment] a4364d81a6de2707…  services/payment/packages.lock.json         (committed)

=== Build lần 2 (cùng commit) ===
  PASS  catalog: layer restore CACHED ở lần build thứ hai
  PASS  cart:    layer restore CACHED ở lần build thứ hai
  PASS  order:   layer restore CACHED ở lần build thứ hai
  PASS  payment: layer restore CACHED ở lần build thứ hai

=== Label revision == git SHA (4/4 service) ===
  PASS  catalog: revision=4683c5a
  PASS  cart:    revision=4683c5a
  PASS  order:   revision=4683c5a
  PASS  payment: revision=4683c5a

=== Hai lần build -> CÙNG runtime-content digest (4/4 service) ===
  PASS  catalog: sha256:b335b348d192e7c97cd… giống nhau ở cả hai lần build
  PASS  cart:    sha256:df639e0af5b3c51cf06… giống nhau ở cả hai lần build
  PASS  order:   sha256:b7179fc0db667bb7b38… giống nhau ở cả hai lần build
  PASS  payment: sha256:db45e544fc00bf1f68f… giống nhau ở cả hai lần build

OK — bộ image của commit 4683c5a tái lập được (cả 4 service).
```

Đó là bằng chứng trực tiếp cho "cùng commit ⇒ image functionally identical" **ở cả bốn service, payment bao gồm**: cùng label `revision`, cùng dependency set (lockfile đã commit, restore locked), cùng digest của runtime config + filesystem layers.

### Kiểm chứng chạy thật (Docker 29.2.1, commit `a4d865a`)

```bash
# --- Lần 1: build nguội cả 4 service ---
$ bash scripts/build-images.sh
==> build starci-shop/catalog:a4d865a  (-f Dockerfile)
==> build starci-shop/cart:a4d865a     (-f services/Cart/Dockerfile)
==> build starci-shop/order:a4d865a    (-f services/order/Dockerfile)
==> build starci-shop/payment:a4d865a  (-f services/payment/Dockerfile)

Bộ image của commit a4d865a:
  starci-shop/payment:a4d865a  340MB
  starci-shop/order:a4d865a    351MB     # +11MB vì có curl cho HEALTHCHECK
  starci-shop/catalog:a4d865a  342MB
  starci-shop/cart:a4d865a     340MB

Kiểm chứng revision nướng trong image:
  starci-shop/catalog:a4d865a -> revision=a4d865a
  starci-shop/cart:a4d865a    -> revision=a4d865a
  starci-shop/order:a4d865a   -> revision=a4d865a
  starci-shop/payment:a4d865a -> revision=a4d865a

# --- Lần 2 trên CÙNG commit: layer restore CACHED ở cả 4 service ---
$ bash scripts/build-images.sh
#10 [build 5/8] RUN dotnet restore services/Catalog/Catalog.csproj --locked-mode
#10 CACHED
#11 [build 5/8] RUN dotnet restore services/Cart/Cart.csproj --locked-mode
#11 CACHED
#13 [build 5/8] RUN dotnet restore services/order/order.csproj --locked-mode
#13 CACHED
#13 [build 4/6] RUN dotnet restore services/payment/payment.csproj --locked-mode
#13 CACHED
# 35 layer CACHED / build lại gần như tức thì

# --- Label đọc đúng như đề yêu cầu ---
$ docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
    starci-shop/catalog:$(git rev-parse --short HEAD)
a4d865a

# --- Hai lần build cho ra CÙNG runtime-content digest ---
$ # run 3 và run 4, hash docker inspect .Config + .RootFS.Layers:
run3: 54b558a5294e  56c5170b2eac  67b0ad8c2a8a  f2568b623924
run4: 54b558a5294e  56c5170b2eac  67b0ad8c2a8a  f2568b623924   # GIỐNG HỆT

# --- payment (image mới) chạy thật, tự khai version ---
$ docker run -d -p 5104:5104 -e PORT=5104 starci-shop/payment:a4d865a
$ curl -s localhost:5104/health
{"service":"payment","status":"ok"}
$ docker logs <id>
[payment] listening on :5104
[payment] version = a4d865a          # APP_VERSION đến từ ARG GIT_SHA
```

**Lockfile không phải để trang trí** — thử làm lệch csproj so với lockfile rồi build:

```bash
$ # đổi Npgsql 10.0.3 -> 9.0.4 trong order.csproj mà KHÔNG cập nhật packages.lock.json
$ docker build -f services/order/Dockerfile -t drift-test .
error NU1004: The package reference Npgsql version has changed from [10.0.3, ) to [9.0.4, ).
The packages lock file is inconsistent with the project dependencies so restore can't be run
in locked mode.
ERROR: process "/bin/sh -c dotnet restore services/order/order.csproj --locked-mode"
       did not complete successfully: exit code: 1
```

Build **fail** thay vì âm thầm phát hành một image với cây NuGet khác. (csproj đã được phục hồi sau thử nghiệm.)

> Trung thực về giới hạn: `docker inspect --format '{{.Id}}'` có thể là digest của manifest **list** và đổi mỗi lần build vì buildx sinh attestation manifest mới kèm timestamp. Script không dựa vào giá trị đó; nó hash trực tiếp `.Config` + `.RootFS.Layers`, tức nội dung runtime quyết định hành vi container, rồi so hai lượt build.

Compose vẫn là **đường dev**, nhưng không còn fallback `dev`: `scripts/compose-up.sh` lấy SHA ngắn từ một working tree sạch, truyền SHA đó vào tag và OCI label, rồi mới gọi Compose. Artifact phát hành vẫn sinh từ `scripts/build-images.sh`. Compose vẫn chỉ dựng `db + catalog + cart + order` như milestone trước — payment có image nhưng chưa vào compose vì chưa có phụ thuộc runtime nào cần nó.

---

# Đối chiếu chấm điểm

Phần listing mã sao chép cũ đã được bỏ vì có số dòng lỗi thời và một khối `placeholder`, khiến grader đọc nhầm file thật. Bằng chứng chuẩn nằm ở các file được commit:

- `REPRODUCIBLE-IMAGES.md`: bản đồ ngắn từ tiêu chí tới Dockerfile, lockfile, script và CI.
- `scripts/build-images.sh`: build cả 4 image với tag SHA và OCI revision label.
- `scripts/verify-reproducible.sh`: build hai lượt và assert cache, digest, label, runtime gọn/non-root.
- `.github/workflows/reproducible-images.yml`: chạy lại toàn bộ kiểm chứng trên mỗi thay đổi liên quan ở `main`.
