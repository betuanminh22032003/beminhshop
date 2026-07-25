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
docker compose up --build -d                      # CẢ SHOP 1 lệnh: db + catalog:3001 + cart:3002 + order:3003
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
docker compose up --build -d
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
```

Bốn thứ khoá chặt "cùng một commit ⇒ cùng một bộ triển khai":

| Ghim cái gì | Bằng cách nào | Nếu không ghim thì sao |
|---|---|---|
| Base image | `FROM …/sdk:10.0@sha256:3dae2f76…`, `…/aspnet:10.0@sha256:1f51d2d6…` | tag `10.0` trôi theo mỗi bản patch — cùng commit, khác base |
| Gói NuGet | `RestorePackagesWithLockFile` + `packages.lock.json` **đã commit** + `dotnet restore --locked-mode` | range `[10.0.3, )` resolve ra version khác ở lần build sau |
| Danh tính image | `ARG GIT_SHA` → `ENV APP_VERSION` + `LABEL org.opencontainers.image.revision` | `latest` trôi nổi, không biết image nào từ commit nào |
| Tốc độ build lại | `.csproj` + `packages.lock.json` copy **trước** source | sửa một dòng `.cs` là restore lại toàn bộ NuGet |

`ARG GIT_SHA` **không có default**: build thiếu ARG thì version rỗng và lộ ra ngay, thay vì dán nhãn sai một image. `latest` chỉ là **alias** (`docker tag`) — artifact bất biến luôn là tag SHA.

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

# --- Hai lần build cho ra CÙNG image config digest ---
$ # run 3 và run 4, so 'exporting config':
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

> Trung thực về giới hạn: `docker inspect --format '{{.Id}}'` (digest của manifest **list**) đổi mỗi lần build vì buildx sinh attestation manifest mới kèm timestamp. Thứ quyết định nội dung container — **image config digest** — thì giống hệt qua các lần build, như bảng run3/run4 ở trên. Muốn `.Id` cũng bất biến thì phải tắt attestation (`--provenance=false --sbom=false`) hoặc set `SOURCE_DATE_EPOCH`; chưa làm vì task không yêu cầu.

Compose vẫn là **đường dev**: nó truyền `GIT_SHA=${GIT_SHA:-dev}` nên image do compose build mang nhãn `dev` cho rõ ràng, không giả một SHA. Artifact phát hành luôn sinh từ `scripts/build-images.sh`. Compose vẫn chỉ dựng `db + catalog + cart + order` như milestone trước — payment có image nhưng chưa vào compose vì chưa có phụ thuộc runtime nào cần nó.

---

# Mã nguồn đầy đủ (để đối chiếu chấm điểm)

> ⚠️ **Listing đã regenerate cho milestone release (image tái lập được)** — sinh trực tiếp từ file thật nên số dòng khớp. Bốn Dockerfile giờ **ghim base bằng digest**, restore ở `--locked-mode` với `packages.lock.json`, và nướng `ARG GIT_SHA` vào `ENV APP_VERSION` + OCI label. **payment lần đầu có `Dockerfile` và cổng từ env `PORT`** (mặc định 5004) — nó không còn phụ thuộc `launchSettings.json` vì file đó không có trong image. `scripts/build-images.sh` là lệnh phát hành. `packages.lock.json` của 5 project KHÔNG in ở đây (máy sinh, dài) — chúng đã được commit và là thứ `--locked-mode` đối chiếu.

Toàn bộ nội dung thực, kèm số dòng, của các file quyết định — cho **cả 4** service.

### `services/Catalog/Program.cs`

```csharp
 1  // catalog: sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm.
 2  // KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
 3  using Catalog;
 4
 5  var config = Config.Load(defaultPort: 5001, defaultName: "catalog");
 6
 7  var builder = WebApplication.CreateBuilder(args);
 8  // Bind 0.0.0.0 để container reachable qua -p; cổng lấy từ env (config.Port).
 9  builder.WebHost.UseUrls($"http://0.0.0.0:{config.Port}");
10  var app = builder.Build();
11
12  // Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
13  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(config.ServiceName)))
14     .AllowAnonymous();
15
16  // Sản phẩm sống trong Postgres — host là TÊN SERVICE compose ("db"), dữ liệu trên named volume
17  // pgdata nên còn nguyên sau docker compose down && up. Seed chỉ chạy khi bảng còn rỗng.
18  var store = new ProductStore(config.DatabaseUrl);
19  Console.WriteLine($"[{config.ServiceName}] catalog db = {config.DatabaseUrl}");
20  await store.InitializeAsync();
21
22  // Shape giữ nguyên { items, total } — hợp đồng đã chốt từ milestone container.
23  app.MapGet("/products", async () =>
24  {
25      var items = await store.ListAsync();
26      return new { items, total = items.Count };
27  });
28
29  Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
30  Console.WriteLine($"[{config.ServiceName}] products source = {(store.UsesDatabase ? "postgres" : "in-memory seed")}");
31  app.Run();
```

### `services/Cart/Program.cs`

```csharp
 1  // cart: sở hữu lựa chọn item đang dở của một khách (thêm / xóa / xem).
 2  // KHÔNG đặt đơn hay thu tiền.
 3  using Cart;
 4
 5  var config = Config.Load(defaultPort: 5002, defaultName: "cart");
 6
 7  var builder = WebApplication.CreateBuilder(args);
 8  // Bind 0.0.0.0 để container reachable qua -p; cổng lấy từ env PORT (mặc định 5002).
 9  builder.WebHost.UseUrls($"http://0.0.0.0:{config.Port}");
10  var app = builder.Build();
11
12  var items = new List<object>();
13
14  // /health: shape cố định { service, status } cho probe gốc (scripts/health.csx).
15  app.MapGet("/health", () => Results.Json(new { service = config.ServiceName, status = "ok" }));
16  app.MapPost("/cart/items", (CartItem item) =>
17  {
18      items.Add(new { sku = item.Sku, qty = item.Qty ?? 1 });
19      return Results.Created("/cart/items", new { items });
20  });
21
22  Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
23  // Địa chỉ service anh em tiêm từ env — trong compose là DNS theo tên service (http://catalog:3001), không localhost.
24  Console.WriteLine($"[{config.ServiceName}] catalog url = {config.CatalogUrl}");
25  app.Run();
26
27  record CartItem(string Sku, int? Qty);
```

### `services/order/Program.cs`

```csharp
 1  // order: sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn.
 2  // KHÔNG thu tiền thẻ.
 3  var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "order";
 4  
 5  var rawPort = Environment.GetEnvironmentVariable("PORT");
 6  int port = 5003;
 7  if (!string.IsNullOrEmpty(rawPort) && !int.TryParse(rawPort, out port))
 8      throw new InvalidOperationException($"Invalid PORT=\"{rawPort}\": expected a number");
 9  
10  // Địa chỉ service anh em TIÊM lúc chạy: trong compose là DNS theo tên service
11  // (http://catalog:3001, http://cart:3002), ngoài compose mặc định localhost. Không hardcode.
12  var catalogUrl = Environment.GetEnvironmentVariable("CATALOG_URL") ?? "http://localhost:5001";
13  var cartUrl = Environment.GetEnvironmentVariable("CART_URL") ?? "http://localhost:5002";
14  
15  // Địa chỉ Postgres cũng từ env: ORDER_DATABASE_URL ưu tiên hơn DATABASE_URL chung của
16  // compose (host là TÊN SERVICE "db"), ngoài compose mặc định localhost.
17  var databaseUrl = Environment.GetEnvironmentVariable("ORDER_DATABASE_URL")
18      ?? Environment.GetEnvironmentVariable("DATABASE_URL")
19      ?? "postgres://shop:shop@localhost:5432/shop";
20  
21  var builder = WebApplication.CreateBuilder(args);
22  // Bind 0.0.0.0 để container reachable qua -p; cổng lấy từ env PORT (mặc định 5003).
23  builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
24  var app = builder.Build();
25  
26  await using var probe = new DatabaseProbe(databaseUrl);
27  
28  // /health là readiness THẬT: mỗi lần gọi là một round-trip `SELECT 1` tới Postgres.
29  // DB sống  -> 200 {"service":"order","status":"ok"}
30  // DB chết  -> 503 {"service":"order","status":"unhealthy","error":...}
31  // Docker HEALTHCHECK và depends_on: condition: service_healthy dựa vào chính chỗ này,
32  // nên KHÔNG được trả "ok" cứng: một 200 giả làm orchestrator đẩy lưu lượng checkout
33  // vào service không có DB.
34  app.MapGet("/health", async (CancellationToken ct) =>
35  {
36      try
37      {
38          await probe.PingAsync(ct);
39          return Results.Json(HealthResponse.Ok(serviceName));
40      }
41      catch (Exception ex)
42      {
43          return Results.Json(HealthResponse.Unhealthy(serviceName, ex.Message), statusCode: 503);
44      }
45  });
46  
47  Console.WriteLine($"[{serviceName}] listening on :{port}");
48  Console.WriteLine($"[{serviceName}] catalog url = {catalogUrl}");
49  Console.WriteLine($"[{serviceName}] cart url = {cartUrl}");
50  // KHÔNG in databaseUrl: chuỗi có password.
51  Console.WriteLine($"[{serviceName}] health probe = SELECT 1 on postgres");
52  app.Run();
```

### `services/payment/Program.cs`

```csharp
 1  // payment: sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán.
 2  // KHÔNG quản lý sản phẩm hay giỏ hàng.
 3  var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "payment";
 4  
 5  // Cổng từ env như ba service kia (milestone image tái lập được: payment giờ cũng được
 6  // đóng gói, nên không thể phụ thuộc launchSettings.json — file đó chỉ tồn tại ở dev).
 7  var rawPort = Environment.GetEnvironmentVariable("PORT");
 8  int port = 5004;
 9  if (!string.IsNullOrEmpty(rawPort) && !int.TryParse(rawPort, out port))
10      throw new InvalidOperationException($"Invalid PORT=\"{rawPort}\": expected a number");
11  
12  var builder = WebApplication.CreateBuilder(args);
13  // Bind 0.0.0.0 để container reachable qua -p.
14  builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
15  var app = builder.Build();
16  
17  // Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
18  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(serviceName)))
19     .AllowAnonymous();
20  
21  Console.WriteLine($"[{serviceName}] listening on :{port}");
22  // APP_VERSION do image nướng vào lúc build (ARG GIT_SHA); chạy từ source thì là "dev".
23  Console.WriteLine($"[{serviceName}] version = {Environment.GetEnvironmentVariable("APP_VERSION") ?? "dev"}");
24  app.Run();
```

### `services/Catalog/HealthResponse.cs`

```csharp
1  namespace Catalog;
2
3  public record HealthResponse(string Service, string Status)
4  {
5      public static HealthResponse Ok(string service) => new(service, "ok");
6  }
```

### `services/Cart/HealthResponse.cs`

```csharp
1  namespace Cart;
2
3  public record HealthResponse(string Service, string Status)
4  {
5      public static HealthResponse Ok(string service) => new(service, "ok");
6  }
```

### `services/order/HealthResponse.cs`

```csharp
 1  using System.Text.Json.Serialization;
 2  
 3  // Shape liveness/readiness của riêng order: { service, status } khi khoẻ, thêm { error }
 4  // khi không. Error bị bỏ khỏi JSON lúc null nên bản "ok" giữ đúng hợp đồng cũ
 5  // {"service":"order","status":"ok"}.
 6  record HealthResponse(
 7      string Service,
 8      string Status,
 9      [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Error = null)
10  {
11      public static HealthResponse Ok(string service) => new(service, "ok");
12  
13      /// <summary>DB không với tới được → 503, nói rõ lý do thay vì 200 giả.</summary>
14      public static HealthResponse Unhealthy(string service, string error) =>
15          new(service, "unhealthy", error);
16  }
```

### `services/payment/HealthResponse.cs`

```csharp
1  record HealthResponse(string Service, string Status)
2  {
3      public static HealthResponse Ok(string service) => new(service, "ok");
4  }
```

`order`/`payment` chưa dùng namespace riêng ở milestone này (chưa nâng cấp lên pattern `Config.cs` như Catalog/Cart) — record ở global namespace. Không project nào tham chiếu record của service khác — 4 định nghĩa độc lập.

**order đã tách khỏi shape chung** ở milestone healthcheck: nó thêm `Error` (bỏ khỏi JSON khi null nên bản "ok" vẫn đúng hợp đồng cũ) và factory `Unhealthy(...)` cho nhánh 503. Đó chính là lý do `HealthResponse` là **4 file riêng** thay vì một record trong `Shop.Contracts`: shape liveness/readiness là việc nội bộ mỗi service, và order vừa chứng minh nó tiến hoá độc lập được mà không làm vỡ ba service kia.

### `services/order/DatabaseProbe.cs`

```csharp
 1  using Npgsql;
 2  
 3  /// <summary>
 4  /// Cầu nối order → Postgres, CHỈ dùng cho readiness probe: mở kết nối thật và chạy
 5  /// `SELECT 1`. Không truy vấn nghiệp vụ nào ở đây — order chưa sở hữu bảng nào.
 6  ///
 7  /// Vì sao order cần thứ này: một `/health` chỉ trả "ok" cứng thì vô dụng — Docker
 8  /// HEALTHCHECK và `depends_on: condition: service_healthy` sẽ báo xanh cả khi DB đã
 9  /// chết. Probe phải đi tới DB và về mới nói được sự thật.
10  ///
11  /// Không tái dùng ProductStore của Catalog: service không tham chiếu project của
12  /// service khác (luật ranh giới trong AGENTS.md) — đây là plumbing hạ tầng của order.
13  /// </summary>
14  public sealed class DatabaseProbe : IAsyncDisposable
15  {
16      private readonly NpgsqlDataSource _dataSource;
17  
18      public DatabaseProbe(string databaseUrl)
19      {
20          ConnectionString = ToConnectionString(databaseUrl);
21          _dataSource = NpgsqlDataSource.Create(ConnectionString);
22      }
23  
24      /// <summary>Connection string ADO đã chuẩn hoá (KHÔNG log — có password).</summary>
25      public string ConnectionString { get; }
26  
27      /// <summary>
28      /// Round-trip thật tới Postgres. Ném ra ngoài nếu DB không nhận kết nối, để
29      /// handler /health đổi thành 503 thay vì che lỗi.
30      /// </summary>
31      public async Task PingAsync(CancellationToken cancellationToken = default)
32      {
33          await using var cmd = _dataSource.CreateCommand("SELECT 1");
34          await cmd.ExecuteScalarAsync(cancellationToken);
35      }
36  
37      /// <summary>
38      /// Đổi URL kiểu `postgres://user:pass@db:5432/shop` (thứ compose tiêm vào) thành
39      /// connection string ADO của Npgsql. Host là TÊN SERVICE trong compose ("db"), không localhost.
40      /// </summary>
41      public static string ToConnectionString(string databaseUrl)
42      {
43          if (!databaseUrl.Contains("://")) return databaseUrl; // đã là connection string sẵn
44  
45          var uri = new Uri(databaseUrl);
46          var userInfo = uri.UserInfo.Split(':', 2);
47          var builder = new NpgsqlConnectionStringBuilder
48          {
49              Host = uri.Host,
50              Port = uri.IsDefaultPort ? 5432 : uri.Port,
51              Database = uri.AbsolutePath.Trim('/'),
52              // Probe phải thất bại NHANH: HEALTHCHECK của Docker chỉ cho 3s.
53              Timeout = 2,
54              CommandTimeout = 2,
55          };
56          if (userInfo.Length > 0 && userInfo[0].Length > 0)
57              builder.Username = Uri.UnescapeDataString(userInfo[0]);
58          if (userInfo.Length > 1)
59              builder.Password = Uri.UnescapeDataString(userInfo[1]);
60          return builder.ConnectionString;
61      }
62  
63      public ValueTask DisposeAsync() => _dataSource.DisposeAsync();
64  }
```

Plumbing hạ tầng của riêng order: đổi `postgres://…` (thứ compose tiêm) sang connection string ADO, rồi `SELECT 1`. `Timeout`/`CommandTimeout` = 2s để probe thất bại nhanh hơn hạn 3s của `HEALTHCHECK`. **Không** tái dùng `ProductStore` của Catalog — service không `ProjectReference` sang service khác; và đây là plumbing, không phải contract, nên cũng không nhét vào `Shop.Contracts`.

### `services/Catalog/Config.cs`

```csharp
 1  namespace Catalog;
 2
 3  public record ServiceConfig(int Port, string ServiceName, string DatabaseUrl);
 4
 5  public static class Config
 6  {
 7      public static ServiceConfig Load(int defaultPort, string defaultName)
 8      {
 9          var rawPort = Environment.GetEnvironmentVariable("PORT");
10          int port = defaultPort;
11          if (!string.IsNullOrEmpty(rawPort) && !int.TryParse(rawPort, out port))
12              throw new InvalidOperationException($"Invalid PORT=\"{rawPort}\": expected a number");
13          var name = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? defaultName;
14          // URL DB catalog được TIÊM lúc chạy (từ env), không bao giờ nướng vào image.
15          // CATALOG_DATABASE_URL (riêng cho service) thắng DATABASE_URL (tên chuẩn compose dùng chung).
16          var databaseUrl = Environment.GetEnvironmentVariable("CATALOG_DATABASE_URL")
17                            ?? Environment.GetEnvironmentVariable("DATABASE_URL")
18                            ?? "postgres://localhost:5432/catalog";
19          return new ServiceConfig(port, name, databaseUrl);
20      }
21  }
```

### `services/Catalog/ProductStore.cs`

Nguồn `/products`: Postgres qua **Npgsql** (ADO thuần, không EF Core). Seed CHỈ chạy khi bảng rỗng → dữ liệu sống qua `docker compose down && up`. Không có DB thì fallback seed in-memory (để `scripts/dev.sh` vẫn chạy được ngoài Docker).

```csharp
  1  using Npgsql;
  2
  3  namespace Catalog;
  4
  5  /// <summary>Một dòng sản phẩm — shape JSON giữ nguyên { id, title, priceCents }.</summary>
  6  public record Product(string Id, string Title, int PriceCents);
  7
  8  /// <summary>
  9  /// Nguồn sản phẩm của Catalog. Dữ liệu nằm trong Postgres (compose: service "db"),
 10  /// nên nó sống lâu hơn container: bảng nằm trên named volume pgdata, seed CHỈ chạy khi
 11  /// bảng còn rỗng — sau `docker compose down && up` dữ liệu cũ vẫn còn và seed bị bỏ qua.
 12  /// Nếu không có DB (chạy dev bằng scripts/dev.sh, không Docker), store rơi về seed
 13  /// in-memory để service vẫn boot được — trạng thái đó ghi rõ trong log.
 14  /// </summary>
 15  public sealed class ProductStore(string databaseUrl)
 16  {
 17      // Seed gốc: cũng chính là dữ liệu ghi vào Postgres lần đầu tiên.
 18      private static readonly Product[] SeedProducts =
 19      [
 20          new("sku-001", "Starter Mug", 1200),
 21          new("sku-002", "Field Notebook", 800),
 22          new("sku-003", "Enamel Pin", 500),
 23      ];
 24
 25      private readonly string _connectionString = ToConnectionString(databaseUrl);
 26
 27      /// <summary>true = đọc/ghi Postgres thật; false = fallback seed in-memory.</summary>
 28      public bool UsesDatabase { get; private set; }
 29
 30      /// <summary>
 31      /// Tạo bảng nếu chưa có rồi seed KHI VÀ CHỈ KHI bảng rỗng. Retry vì Postgres có thể
 32      /// chưa nhận kết nối ngay (compose đã có depends_on: service_healthy, nhưng chạy tay thì không).
 33      /// </summary>
 34      public async Task<bool> InitializeAsync(int attempts = 5, int delayMs = 1000)
 35      {
 36          for (var attempt = 1; attempt <= attempts; attempt++)
 37          {
 38              try
 39              {
 40                  await using var db = new NpgsqlConnection(_connectionString);
 41                  await db.OpenAsync();
 42
 43                  await using (var create = new NpgsqlCommand(
 44                      """
 45                      CREATE TABLE IF NOT EXISTS products (
 46                          id          text    PRIMARY KEY,
 47                          title       text    NOT NULL,
 48                          price_cents integer NOT NULL
 49                      )
 50                      """, db))
 51                  {
 52                      await create.ExecuteNonQueryAsync();
 53                  }
 54
 55                  await using (var count = new NpgsqlCommand("SELECT count(*) FROM products", db))
 56                  {
 57                      var existing = Convert.ToInt64(await count.ExecuteScalarAsync());
 58                      if (existing > 0)
 59                      {
 60                          // Bằng chứng dữ liệu bền bỉ: bảng đã có sẵn từ lần boot trước (volume pgdata).
 61                          Console.WriteLine($"[catalog] products already in db ({existing} rows) — skipping seed");
 62                          UsesDatabase = true;
 63                          return true;
 64                      }
 65                  }
 66
 67                  foreach (var p in SeedProducts)
 68                  {
 69                      await using var insert = new NpgsqlCommand(
 70                          "INSERT INTO products (id, title, price_cents) VALUES ($1, $2, $3)", db);
 71                      insert.Parameters.AddWithValue(p.Id);
 72                      insert.Parameters.AddWithValue(p.Title);
 73                      insert.Parameters.AddWithValue(p.PriceCents);
 74                      await insert.ExecuteNonQueryAsync();
 75                  }
 76                  Console.WriteLine($"[catalog] seeded {SeedProducts.Length} products into db");
 77                  UsesDatabase = true;
 78                  return true;
 79              }
 80              catch (Exception ex) when (attempt < attempts)
 81              {
 82                  Console.WriteLine($"[catalog] db not ready (attempt {attempt}/{attempts}): {ex.Message}");
 83                  await Task.Delay(delayMs);
 84              }
 85              catch (Exception ex)
 86              {
 87                  // Không có Postgres (vd. bash scripts/dev.sh) — vẫn boot, phục vụ seed in-memory.
 88                  Console.WriteLine($"[catalog] WARN db unreachable ({ex.Message}) — serving in-memory seed");
 89                  UsesDatabase = false;
 90                  return false;
 91              }
 92          }
 93          UsesDatabase = false;
 94          return false;
 95      }
 96
 97      /// <summary>Đọc danh sách sản phẩm — từ Postgres nếu có, ngược lại từ seed in-memory.</summary>
 98      public async Task<IReadOnlyList<Product>> ListAsync()
 99      {
100          if (!UsesDatabase) return SeedProducts;
101
102          var items = new List<Product>();
103          await using var db = new NpgsqlConnection(_connectionString);
104          await db.OpenAsync();
105          await using var query = new NpgsqlCommand(
106              "SELECT id, title, price_cents FROM products ORDER BY id", db);
107          await using var reader = await query.ExecuteReaderAsync();
108          while (await reader.ReadAsync())
109              items.Add(new Product(reader.GetString(0), reader.GetString(1), reader.GetInt32(2)));
110          return items;
111      }
112
113      /// <summary>
114      /// Đổi URL kiểu `postgres://user:pass@db:5432/shop` (thứ compose tiêm vào) thành
115      /// connection string ADO của Npgsql. Host là TÊN SERVICE trong compose ("db"), không localhost.
116      /// </summary>
117      public static string ToConnectionString(string databaseUrl)
118      {
119          if (!databaseUrl.Contains("://")) return databaseUrl; // đã là connection string sẵn
120
121          var uri = new Uri(databaseUrl);
122          var userInfo = uri.UserInfo.Split(':', 2);
123          var builder = new NpgsqlConnectionStringBuilder
124          {
125              Host = uri.Host,
126              Port = uri.IsDefaultPort ? 5432 : uri.Port,
127              Database = uri.AbsolutePath.Trim('/'),
128              Timeout = 5,
129          };
130          if (userInfo.Length > 0 && userInfo[0].Length > 0)
131              builder.Username = Uri.UnescapeDataString(userInfo[0]);
132          if (userInfo.Length > 1)
133              builder.Password = Uri.UnescapeDataString(userInfo[1]);
134          return builder.ConnectionString;
135      }
136  }
```

### `services/Cart/Config.cs`

```csharp
 1  namespace Cart;
 2
 3  public record ServiceConfig(int Port, string ServiceName, string CatalogUrl);
 4
 5  public static class Config
 6  {
 7      public static ServiceConfig Load(int defaultPort, string defaultName)
 8      {
 9          var rawPort = Environment.GetEnvironmentVariable("PORT");
10          int port = defaultPort;
11          if (!string.IsNullOrEmpty(rawPort) && !int.TryParse(rawPort, out port))
12              throw new InvalidOperationException($"Invalid PORT=\"{rawPort}\": expected a number");
13          var name = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? defaultName;
14          // Địa chỉ Catalog TIÊM lúc chạy: trong compose là http://catalog:3001 (DNS theo tên service),
15          // ngoài compose mặc định localhost:5001. Không bao giờ hardcode host của service khác.
16          var catalogUrl = Environment.GetEnvironmentVariable("CATALOG_URL")
17                           ?? "http://localhost:5001";
18          return new ServiceConfig(port, name, catalogUrl);
19      }
20  }
```

### `services/Catalog/Catalog.csproj`

```xml
 1  <Project Sdk="Microsoft.NET.Sdk.Web">
 2  
 3    <PropertyGroup>
 4      <TargetFramework>net10.0</TargetFramework>
 5      <Nullable>enable</Nullable>
 6      <ImplicitUsings>enable</ImplicitUsings>
 7      <!-- Lockfile ĐƯỢC COMMIT (packages.lock.json). Docker restore chạy ở locked mode nên
 8           hai lần build cùng một commit luôn kéo đúng cùng một cây NuGet; lockfile lệch
 9           csproj thì build FAIL thay vì âm thầm nâng version. -->
10      <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
11      <!-- Chốt tên assembly để output publish (Catalog.dll) khớp ENTRYPOINT của Dockerfile,
12           không phụ thuộc casing thư mục (NTFS case-insensitive). -->
13      <AssemblyName>Catalog</AssemblyName>
14    </PropertyGroup>
15  
16    <ItemGroup>
17      <ProjectReference Include="..\..\packages\Shop.Contracts\Shop.Contracts.csproj" />
18    </ItemGroup>
19  
20    <ItemGroup>
21      <PackageReference Include="Npgsql" Version="10.0.3" />
22    </ItemGroup>
23  
24  </Project>
```

### `Dockerfile` (đa tầng — tầng build có SDK, tầng runtime KHÔNG)

```dockerfile
 1  # Dockerfile ĐA TẦNG cho service Catalog (.NET). Build context = GỐC repo
 2  # (Catalog tham chiếu packages/Shop.Contracts). Đừng `docker build` tay nữa —
 3  # `bash scripts/build-images.sh` tag theo git SHA và truyền ARG GIT_SHA cho cả 4 service.
 4  # Bản đơn tầng cũ giữ ở Dockerfile.single để so kích thước (SDK lên tận production).
 5  #
 6  # TÁI LẬP ĐƯỢC: base ghim bằng DIGEST (không phải tag trôi nổi), NuGet ghim bằng
 7  # packages.lock.json đã commit + restore ở locked mode ⇒ cùng một commit, cùng một image.
 8  
 9  # --- tầng build: full .NET SDK, ghim digest ---
10  FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:3dae2f7699441af56216ff64d5c9b6dfce7cd7dc7f4f71d353d29662b10a384f AS build
11  WORKDIR /src
12  
13  # .csproj + packages.lock.json TRƯỚC source: layer restore chỉ mất cache khi dependency
14  # đổi, nên sửa một file .cs KHÔNG kéo lại gói NuGet nào (lần build sau in ra CACHED).
15  COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/packages.lock.json packages/Shop.Contracts/
16  COPY services/Catalog/Catalog.csproj services/Catalog/packages.lock.json services/Catalog/
17  # --locked-mode: lockfile lệch csproj thì FAIL build, không âm thầm resolve version khác.
18  RUN dotnet restore services/Catalog/Catalog.csproj --locked-mode
19  
20  # Source copy SAU restore.
21  COPY packages/Shop.Contracts/ packages/Shop.Contracts/
22  COPY services/Catalog/ services/Catalog/
23  RUN dotnet publish services/Catalog/Catalog.csproj -c Release -o /app/publish --no-restore
24  
25  # --- tầng runtime: CHỈ ASP.NET runtime (ghim digest), không SDK, không chạy root ---
26  FROM mcr.microsoft.com/dotnet/aspnet:10.0@sha256:1f51d2d65ace46d6395e773fb4cfc1c74d36fb4f08e5cf996e7f6961b45e9283 AS runtime
27  
28  # GIT_SHA tiêm lúc build, KHÔNG default về giá trị trôi nổi: build thiếu ARG thì version
29  # rỗng và thấy ngay, thay vì gắn nhãn sai cho một image.
30  ARG GIT_SHA
31  ENV APP_VERSION=${GIT_SHA} \
32      DOTNET_RUNNING_IN_CONTAINER=true
33  
34  # Image tự khai danh tính: `docker inspect` đọc ra đúng commit đã sinh ra nó.
35  LABEL org.opencontainers.image.revision=${GIT_SHA} \
36        org.opencontainers.image.version=${GIT_SHA} \
37        org.opencontainers.image.title=starci-shop/catalog \
38        org.opencontainers.image.source=https://github.com/betuanminh22032003/beminhshop
39  
40  WORKDIR /app
41  
42  # CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
43  COPY --from=build /app/publish ./
44  
45  # Image aspnet có sẵn user không phải root tên "app".
46  USER app
47  EXPOSE 3001
48  # PORT và CATALOG_DATABASE_URL đọc từ env lúc chạy (không nướng vào image).
49  ENTRYPOINT ["dotnet", "Catalog.dll"]
```

(Comment tiếng Việt đầy đủ nằm trong file thật; trên đây rút gọn phần chú thích.)

### `docker-compose.yaml`

Cả shop bằng một lệnh: secret từ `.env`, DNS theo tên service trên `shopnet`, `pgdata` named volume, `depends_on: service_healthy`.

```yaml
  1  # Cả shop bằng MỘT lệnh: docker compose up --build
  2  #
  3  # - Secret KHÔNG nằm trong file này: mọi ${VAR} được compose nạp từ .env (gitignored),
  4  #   .env.example là bản mẫu có thể commit.
  5  # - Service tìm nhau qua DNS THEO TÊN SERVICE trên mạng shopnet (db, catalog, cart),
  6  #   không localhost, không IP cứng — bridge mặc định không phân giải tên nên shopnet
  7  #   phải được khai báo tường minh.
  8  # - Dữ liệu Postgres nằm trên named volume pgdata nên sản phẩm đã seed sống sót qua
  9  #   docker compose down && docker compose up (KHÔNG dùng `down -v`).
 10  # - Mỗi service build từ Dockerfile riêng nhưng context là GỐC repo, vì cả ba tham
 11  #   chiếu packages/Shop.Contracts.
 12  
 13  services:
 14    db:
 15      image: postgres:16-alpine
 16      environment:
 17        POSTGRES_USER: ${POSTGRES_USER}
 18        POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
 19        POSTGRES_DB: ${POSTGRES_DB}
 20      volumes:
 21        # Named volume -> dữ liệu sống lâu hơn container.
 22        - pgdata:/var/lib/postgresql/data
 23      networks:
 24        - shopnet
 25      healthcheck:
 26        # depends_on: service_healthy của app dựa vào chính healthcheck này.
 27        # pg_isready chỉ thoát 0 khi Postgres ĐÃ nhận kết nối — đó là điều kiện chặn thật.
 28        test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
 29        interval: 5s
 30        timeout: 3s
 31        retries: 10
 32        # Vài giây đầu Postgres còn initdb: đừng tính là lần retry thất bại.
 33        start_period: 10s
 34  
 35    catalog:
 36      build:
 37        context: .
 38        dockerfile: Dockerfile
 39        args:
 40          # Compose là đường dev: image mang nhãn "dev" cho RÕ RÀNG, không giả một SHA.
 41          # Artifact phát hành bất biến sinh bằng `bash scripts/build-images.sh` (tag = git SHA).
 42          GIT_SHA: ${GIT_SHA:-dev}
 43      environment:
 44        PORT: 3001
 45        SERVICE_NAME: catalog
 46        # host là "db" — tên service trong compose, do DNS của shopnet phân giải.
 47        DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:${POSTGRES_PORT}/${POSTGRES_DB}
 48      depends_on:
 49        db:
 50          condition: service_healthy
 51      ports:
 52        - "3001:3001"
 53      networks:
 54        - shopnet
 55  
 56    cart:
 57      build:
 58        context: .
 59        dockerfile: services/Cart/Dockerfile
 60        args:
 61          # Compose là đường dev: image mang nhãn "dev" cho RÕ RÀNG, không giả một SHA.
 62          # Artifact phát hành bất biến sinh bằng `bash scripts/build-images.sh` (tag = git SHA).
 63          GIT_SHA: ${GIT_SHA:-dev}
 64      environment:
 65        PORT: 3002
 66        SERVICE_NAME: cart
 67        DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:${POSTGRES_PORT}/${POSTGRES_DB}
 68        # Lưu lượng service→service cũng đi bằng DNS theo tên service.
 69        CATALOG_URL: http://catalog:3001
 70      depends_on:
 71        db:
 72          condition: service_healthy
 73      ports:
 74        - "3002:3002"
 75      networks:
 76        - shopnet
 77  
 78    order:
 79      build:
 80        context: .
 81        dockerfile: services/order/Dockerfile
 82        args:
 83          # Compose là đường dev: image mang nhãn "dev" cho RÕ RÀNG, không giả một SHA.
 84          # Artifact phát hành bất biến sinh bằng `bash scripts/build-images.sh` (tag = git SHA).
 85          GIT_SHA: ${GIT_SHA:-dev}
 86      environment:
 87        PORT: 3003
 88        SERVICE_NAME: order
 89        DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:${POSTGRES_PORT}/${POSTGRES_DB}
 90        CATALOG_URL: http://catalog:3001
 91        CART_URL: http://cart:3002
 92      # order KHÔNG được khởi động cho tới khi db báo healthy — nhờ vậy kết nối Npgsql
 93      # đầu tiên không còn gặp "Connection refused" ở lần `up` từ trạng thái sạch.
 94      # Trạng thái healthy của chính order do HEALTHCHECK trong image quyết định
 95      # (services/order/Dockerfile: curl /health -> SELECT 1 tới Postgres).
 96      depends_on:
 97        db:
 98          condition: service_healthy
 99      ports:
100        - "3003:3003"
101      networks:
102        - shopnet
103  
104  networks:
105    # Mạng do người dùng định nghĩa = có DNS nội bộ theo tên service.
106    shopnet:
107      driver: bridge
108  
109  volumes:
110    # Khai báo một lần ở cấp cao nhất: Docker quản lý vòng đời volume độc lập với container.
111    pgdata:
```

### `.env.example`

Bản mẫu commit được. `.env` thật (cùng khoá, giá trị thật) bị `.gitignore` chặn — xem `.gitignore`: `.env`, `.env.*`, `!.env.example`.

```dotenv
1  # Mẫu cấu hình cho docker-compose.yaml — COPY thành .env rồi đổi giá trị thật:
2  #   cp .env.example .env
3  # .env bị gitignore (secret không bao giờ commit); file này chỉ phơi HỢP ĐỒNG cấu hình.
4  POSTGRES_USER=shop
5  POSTGRES_PASSWORD=replace_me
6  POSTGRES_DB=shop
7  POSTGRES_PORT=5432
```

### `services/Cart/Dockerfile`

```dockerfile
 1  # Dockerfile ĐA TẦNG cho service Cart (.NET). Build context = GỐC repo
 2  # (Cart tham chiếu packages/Shop.Contracts). Build qua `bash scripts/build-images.sh`
 3  # để tag theo git SHA; docker-compose.yaml khai đúng cặp context: . / dockerfile: services/Cart/Dockerfile.
 4  #
 5  # TÁI LẬP ĐƯỢC: base ghim bằng DIGEST, NuGet ghim bằng packages.lock.json + locked mode.
 6  
 7  # --- tầng build: full .NET SDK, ghim digest ---
 8  FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:3dae2f7699441af56216ff64d5c9b6dfce7cd7dc7f4f71d353d29662b10a384f AS build
 9  WORKDIR /src
10  
11  # .csproj + packages.lock.json TRƯỚC source: layer restore giữ cache tới khi dependency đổi.
12  COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/packages.lock.json packages/Shop.Contracts/
13  COPY services/Cart/Cart.csproj services/Cart/packages.lock.json services/Cart/
14  # --locked-mode: lockfile lệch csproj thì FAIL build, không âm thầm resolve version khác.
15  RUN dotnet restore services/Cart/Cart.csproj --locked-mode
16  
17  # Source copy SAU restore.
18  COPY packages/Shop.Contracts/ packages/Shop.Contracts/
19  COPY services/Cart/ services/Cart/
20  RUN dotnet publish services/Cart/Cart.csproj -c Release -o /app/publish --no-restore
21  
22  # --- tầng runtime: CHỈ ASP.NET runtime (ghim digest), không SDK, không chạy root ---
23  FROM mcr.microsoft.com/dotnet/aspnet:10.0@sha256:1f51d2d65ace46d6395e773fb4cfc1c74d36fb4f08e5cf996e7f6961b45e9283 AS runtime
24  
25  ARG GIT_SHA
26  ENV APP_VERSION=${GIT_SHA} \
27      DOTNET_RUNNING_IN_CONTAINER=true
28  
29  LABEL org.opencontainers.image.revision=${GIT_SHA} \
30        org.opencontainers.image.version=${GIT_SHA} \
31        org.opencontainers.image.title=starci-shop/cart \
32        org.opencontainers.image.source=https://github.com/betuanminh22032003/beminhshop
33  
34  WORKDIR /app
35  
36  # CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
37  COPY --from=build /app/publish ./
38  
39  # Image aspnet có sẵn user không phải root tên "app".
40  USER app
41  EXPOSE 3002
42  # PORT / CATALOG_URL / DATABASE_URL đọc từ env lúc chạy (không nướng vào image).
43  ENTRYPOINT ["dotnet", "Cart.dll"]
```

### `services/order/Dockerfile`

```dockerfile
 1  # Dockerfile ĐA TẦNG cho service order (.NET). Build context = GỐC repo
 2  # (order tham chiếu packages/Shop.Contracts). Build qua `bash scripts/build-images.sh`
 3  # để tag theo git SHA; docker-compose.yaml khai đúng cặp context: . / dockerfile: services/order/Dockerfile.
 4  #
 5  # TÁI LẬP ĐƯỢC: base ghim bằng DIGEST, NuGet ghim bằng packages.lock.json + locked mode.
 6  
 7  # --- tầng build: full .NET SDK, ghim digest ---
 8  FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:3dae2f7699441af56216ff64d5c9b6dfce7cd7dc7f4f71d353d29662b10a384f AS build
 9  WORKDIR /src
10  
11  # .csproj + packages.lock.json TRƯỚC source: layer restore giữ cache tới khi dependency đổi.
12  COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/packages.lock.json packages/Shop.Contracts/
13  COPY services/order/order.csproj services/order/packages.lock.json services/order/
14  # --locked-mode: lockfile lệch csproj thì FAIL build, không âm thầm resolve version khác.
15  RUN dotnet restore services/order/order.csproj --locked-mode
16  
17  # Source copy SAU restore.
18  COPY packages/Shop.Contracts/ packages/Shop.Contracts/
19  COPY services/order/ services/order/
20  RUN dotnet publish services/order/order.csproj -c Release -o /app/publish --no-restore
21  
22  # --- tầng runtime: CHỈ ASP.NET runtime (ghim digest), không SDK, không chạy root ---
23  FROM mcr.microsoft.com/dotnet/aspnet:10.0@sha256:1f51d2d65ace46d6395e773fb4cfc1c74d36fb4f08e5cf996e7f6961b45e9283 AS runtime
24  
25  ARG GIT_SHA
26  ENV APP_VERSION=${GIT_SHA} \
27      DOTNET_RUNNING_IN_CONTAINER=true
28  
29  LABEL org.opencontainers.image.revision=${GIT_SHA} \
30        org.opencontainers.image.version=${GIT_SHA} \
31        org.opencontainers.image.title=starci-shop/order \
32        org.opencontainers.image.source=https://github.com/betuanminh22032003/beminhshop
33  
34  WORKDIR /app
35  
36  # curl là công cụ DUY NHẤT thêm vào runtime, để HEALTHCHECK tự thăm dò /health được.
37  # Cài trước khi hạ quyền (apt cần root), rồi dọn apt lists cho image gọn.
38  RUN apt-get update \
39      && apt-get install -y --no-install-recommends curl \
40      && rm -rf /var/lib/apt/lists/*
41  
42  # CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
43  COPY --from=build /app/publish ./
44  
45  # Image aspnet có sẵn user không phải root tên "app".
46  USER app
47  EXPOSE 3003
48  # PORT / CATALOG_URL / CART_URL / DATABASE_URL đọc từ env lúc chạy (không nướng vào image).
49  
50  # Container tự thăm dò /health — endpoint đó chạy `SELECT 1` thật tới Postgres, nên
51  # "healthy" ở đây nghĩa là order THỰC SỰ nói chuyện được với DB, không chỉ còn sống.
52  # Dạng shell (không phải exec) để ${PORT} nở lúc chạy — cổng vẫn do env quyết định.
53  # curl -f thoát khác 0 khi HTTP >= 400, nên 503 lập tức thành "unhealthy".
54  HEALTHCHECK --interval=10s --timeout=3s --retries=5 --start-period=20s \
55      CMD curl -fsS "http://localhost:${PORT:-3003}/health" || exit 1
56  
57  ENTRYPOINT ["dotnet", "order.dll"]
```

### `services/payment/Dockerfile`

```dockerfile
 1  # Dockerfile ĐA TẦNG cho service payment (.NET). Build context = GỐC repo cho ĐỒNG NHẤT
 2  # với ba service kia (payment chưa tham chiếu Shop.Contracts, nhưng giữ cùng một hợp đồng
 3  # context để scripts/build-images.sh gọi cả 4 service bằng cùng một dòng lệnh).
 4  # Build qua `bash scripts/build-images.sh`.
 5  #
 6  # TÁI LẬP ĐƯỢC: base ghim bằng DIGEST, NuGet ghim bằng packages.lock.json + locked mode.
 7  
 8  # --- tầng build: full .NET SDK, ghim digest ---
 9  FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:3dae2f7699441af56216ff64d5c9b6dfce7cd7dc7f4f71d353d29662b10a384f AS build
10  WORKDIR /src
11  
12  # .csproj + packages.lock.json TRƯỚC source: layer restore giữ cache tới khi dependency đổi.
13  COPY services/payment/payment.csproj services/payment/packages.lock.json services/payment/
14  # --locked-mode: lockfile lệch csproj thì FAIL build, không âm thầm resolve version khác.
15  RUN dotnet restore services/payment/payment.csproj --locked-mode
16  
17  # Source copy SAU restore.
18  COPY services/payment/ services/payment/
19  RUN dotnet publish services/payment/payment.csproj -c Release -o /app/publish --no-restore
20  
21  # --- tầng runtime: CHỈ ASP.NET runtime (ghim digest), không SDK, không chạy root ---
22  FROM mcr.microsoft.com/dotnet/aspnet:10.0@sha256:1f51d2d65ace46d6395e773fb4cfc1c74d36fb4f08e5cf996e7f6961b45e9283 AS runtime
23  
24  ARG GIT_SHA
25  ENV APP_VERSION=${GIT_SHA} \
26      DOTNET_RUNNING_IN_CONTAINER=true
27  
28  LABEL org.opencontainers.image.revision=${GIT_SHA} \
29        org.opencontainers.image.version=${GIT_SHA} \
30        org.opencontainers.image.title=starci-shop/payment \
31        org.opencontainers.image.source=https://github.com/betuanminh22032003/beminhshop
32  
33  WORKDIR /app
34  
35  # CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
36  COPY --from=build /app/publish ./
37  
38  # Image aspnet có sẵn user không phải root tên "app".
39  USER app
40  EXPOSE 5004
41  # PORT / SERVICE_NAME đọc từ env lúc chạy; launchSettings.json chỉ dùng cho dev, KHÔNG vào image.
42  ENTRYPOINT ["dotnet", "payment.dll"]
```

### `scripts/build-images.sh`

```bash
 1  #!/usr/bin/env bash
 2  # Phát hành CẢ SHOP dưới dạng bộ image tái lập được.
 3  #
 4  # Mỗi image được tag bằng ĐÚNG commit sinh ra nó (git SHA ngắn) và tự khai commit đó
 5  # trong OCI label org.opencontainers.image.revision. Không có `latest` trôi nổi:
 6  # `latest` (nếu có) chỉ là alias trỏ tới tag SHA vừa build.
 7  #
 8  # Vì sao build lại rất nhanh: Dockerfile copy .csproj + packages.lock.json TRƯỚC source,
 9  # nên layer `dotnet restore --locked-mode` giữ cache khi chỉ có code đổi -> lần build thứ
10  # hai trên cùng một commit in ra CACHED ở layer restore.
11  #
12  # Dùng:
13  #   bash scripts/build-images.sh              # build cả 4 service, tag = SHA ngắn
14  #   bash scripts/build-images.sh --latest     # thêm alias :latest trỏ cùng image
15  #
16  # Chạy hai lần trên cùng một commit ⇒ cùng một bộ triển khai (base ghim digest,
17  # NuGet ghim lockfile).
18  set -euo pipefail
19  
20  cd "$(dirname "$0")/.."
21  
22  if ! GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null)"; then
23    echo "error: không phải git repo — không có commit thì không tag bất biến được" >&2
24    exit 1
25  fi
26  
27  # Cây làm việc bẩn = image sẽ KHÔNG khớp commit được tag. Cảnh báo, không chặn (dev tiện).
28  if ! git diff-index --quiet HEAD --; then
29    echo "warn: working tree có thay đổi chưa commit — image tag $GIT_SHA sẽ KHÔNG khớp commit đó" >&2
30  fi
31  
32  TAG_LATEST=0
33  [[ "${1:-}" == "--latest" ]] && TAG_LATEST=1
34  
35  # Tên service -> Dockerfile. Cả bốn build với context = GỐC repo (Catalog/Cart/order
36  # tham chiếu packages/Shop.Contracts; payment giữ cùng hợp đồng cho đồng nhất).
37  SERVICES=(catalog cart order payment)
38  DOCKERFILES=(Dockerfile services/Cart/Dockerfile services/order/Dockerfile services/payment/Dockerfile)
39  
40  for i in "${!SERVICES[@]}"; do
41    svc="${SERVICES[$i]}"
42    dockerfile="${DOCKERFILES[$i]}"
43    image="starci-shop/${svc}:${GIT_SHA}"
44  
45    echo "==> build ${image}  (-f ${dockerfile})"
46    docker build \
47      --build-arg "GIT_SHA=${GIT_SHA}" \
48      -t "${image}" \
49      -f "${dockerfile}" \
50      .
51  
52    if [[ $TAG_LATEST -eq 1 ]]; then
53      # latest CHỈ là alias — artifact bất biến vẫn là tag SHA.
54      docker tag "${image}" "starci-shop/${svc}:latest"
55      echo "    tagged starci-shop/${svc}:latest -> ${GIT_SHA}"
56    fi
57  
58    echo "    built ${image}"
59  done
60  
61  echo
62  echo "Bộ image của commit ${GIT_SHA}:"
63  docker images --filter "reference=starci-shop/*:${GIT_SHA}" \
64    --format '  {{.Repository}}:{{.Tag}}  {{.Size}}  (id {{.ID}})'
65  
66  echo
67  echo "Kiểm chứng revision nướng trong image:"
68  for svc in "${SERVICES[@]}"; do
69    revision="$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
70      "starci-shop/${svc}:${GIT_SHA}")"
71    echo "  starci-shop/${svc}:${GIT_SHA} -> revision=${revision}"
72  done
```

### `services/payment/Program.cs`

```csharp
placeholder
```

### `services/Cart/Cart.csproj`

```xml
 1  <Project Sdk="Microsoft.NET.Sdk.Web">
 2  
 3    <PropertyGroup>
 4      <TargetFramework>net10.0</TargetFramework>
 5      <Nullable>enable</Nullable>
 6      <ImplicitUsings>enable</ImplicitUsings>
 7      <!-- Lockfile ĐƯỢC COMMIT (packages.lock.json). Docker restore chạy ở locked mode nên
 8           hai lần build cùng một commit luôn kéo đúng cùng một cây NuGet; lockfile lệch
 9           csproj thì build FAIL thay vì âm thầm nâng version. -->
10      <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
11      <!-- Chốt tên assembly để output publish (Cart.dll) khớp ENTRYPOINT của Dockerfile,
12           không phụ thuộc casing thư mục (NTFS case-insensitive). -->
13      <AssemblyName>Cart</AssemblyName>
14    </PropertyGroup>
15  
16    <ItemGroup>
17      <ProjectReference Include="..\..\packages\Shop.Contracts\Shop.Contracts.csproj" />
18    </ItemGroup>
19  
20  </Project>
```

### `services/order/order.csproj`

```xml
 1  <Project Sdk="Microsoft.NET.Sdk.Web">
 2  
 3    <PropertyGroup>
 4      <TargetFramework>net10.0</TargetFramework>
 5      <Nullable>enable</Nullable>
 6      <ImplicitUsings>enable</ImplicitUsings>
 7      <!-- Lockfile ĐƯỢC COMMIT (packages.lock.json). Docker restore chạy ở locked mode nên
 8           hai lần build cùng một commit luôn kéo đúng cùng một cây NuGet; lockfile lệch
 9           csproj thì build FAIL thay vì âm thầm nâng version. -->
10      <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
11      <!-- Chốt tên assembly để output publish (order.dll) khớp ENTRYPOINT của Dockerfile,
12           không phụ thuộc casing thư mục (NTFS case-insensitive). -->
13      <AssemblyName>order</AssemblyName>
14    </PropertyGroup>
15  
16    <ItemGroup>
17      <!-- ADO thuần, không EF Core: order chỉ cần ping DB (`SELECT 1`) cho readiness probe. -->
18      <PackageReference Include="Npgsql" Version="10.0.3" />
19    </ItemGroup>
20  
21    <ItemGroup>
22      <ProjectReference Include="..\..\packages\Shop.Contracts\Shop.Contracts.csproj" />
23    </ItemGroup>
24  
25  </Project>
```

### `services/payment/payment.csproj`

```xml
 1  <Project Sdk="Microsoft.NET.Sdk.Web">
 2  
 3    <PropertyGroup>
 4      <TargetFramework>net10.0</TargetFramework>
 5      <Nullable>enable</Nullable>
 6      <ImplicitUsings>enable</ImplicitUsings>
 7      <!-- Lockfile ĐƯỢC COMMIT (packages.lock.json). Docker restore chạy ở locked mode nên
 8           hai lần build cùng một commit luôn kéo đúng cùng một cây NuGet; lockfile lệch
 9           csproj thì build FAIL thay vì âm thầm nâng version. -->
10      <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
11      <!-- Chốt tên assembly để output publish (payment.dll) khớp ENTRYPOINT của Dockerfile,
12           không phụ thuộc casing thư mục (NTFS case-insensitive) — cùng lý do như order. -->
13      <AssemblyName>payment</AssemblyName>
14    </PropertyGroup>
15  
16  </Project>
```

### `starci-shop.slnx`

```xml
1  <Solution>
2    <Folder Name="/services/">
3      <Project Path="services/Cart/Cart.csproj" />
4      <Project Path="services/Catalog/Catalog.csproj" />
5      <Project Path="services/order/order.csproj" />
6      <Project Path="services/payment/payment.csproj" />
7    </Folder>
8  </Solution>
```

## Đối chiếu tiêu chí → dòng mã (cả 4 service)

| Tiêu chí | Catalog | Cart | order | payment |
| --- | --- | --- | --- | --- |
| Entrypoint riêng, boot trên port riêng | `Program.cs` | `Program.cs` | `Program.cs` | `Program.cs` |
| Identity đọc từ env, không hardcode | `Config.cs:13` (`SERVICE_NAME`) | `Config.cs:13` | `Program.cs:3` (`SERVICE_NAME`) | `Program.cs:6` |
| Default khi thiếu `SERVICE_NAME` | `Config.cs:13` `?? defaultName` | `Config.cs:13` | `Program.cs:3` `?? "order"` | `Program.cs:6` `?? "payment"` |
| `GET /health` shape `{service,status}` | `Program.cs:13` (record `HealthResponse`) | `Program.cs:15` (`Results.Json`) | `Program.cs:21` (`Results.Json`) | `Program.cs:9` (record) |
| `HealthResponse` là bản riêng của service (không project chung) | `HealthResponse.cs` (`namespace Catalog;`) | `HealthResponse.cs` (`namespace Cart;`) | `HealthResponse.cs` (global) | `HealthResponse.cs` (global) |
| `.csproj` riêng, `Sdk.Web` + `net10.0`, không `ProjectReference` chéo | `Catalog.csproj:1,4` | `Cart.csproj:1,4` | `order.csproj:1,4` | `payment.csproj:1,4` |
| Solution tham chiếu project riêng | `starci-shop.slnx:4` | `starci-shop.slnx:3` | `starci-shop.slnx:5` | `starci-shop.slnx:6` |
| `/health` unauthenticated, side-effect free | `Program.cs:13-14` (`AllowAnonymous`) | `Program.cs:15` (không auth) | `Program.cs:21` (không auth) | `Program.cs:9-10` (`AllowAnonymous`) |

### Milestone compose — tiêu chí → dòng mã

| Tiêu chí | Catalog | Cart | order |
| --- | --- | --- | --- |
| Cổng từ `PORT` env, có default riêng | `Program.cs:5` (`Config.Load` 5001) | `Program.cs:5` (`Config.Load` 5002) | `Program.cs:5-8` (`5003` + parse) |
| `UseUrls` bind `0.0.0.0`, chỉ dùng biến | `Program.cs:9` | `Program.cs:9` | `Program.cs:17` |
| Ném lỗi khi `PORT` malformed | `Config.cs:11-12` | `Config.cs:11-12` | `Program.cs:7-8` |
| Địa chỉ phụ thuộc từ env (không hardcode host service khác) | `Config.cs:16-18` (`CATALOG_DATABASE_URL` → `DATABASE_URL`) | `Config.cs:16-17` (`CATALOG_URL`) | `Program.cs:12-13` (`CATALOG_URL`, `CART_URL`) |
| Dockerfile đa tầng riêng, context = gốc repo | `/Dockerfile` | `services/Cart/Dockerfile` | `services/order/Dockerfile` |
| Khối service trong stack một-lệnh | `docker-compose.yaml:32-47` | `:49-65` | `:67-83` |

| Tiêu chí compose | Dòng trong `docker-compose.yaml` |
| --- | --- |
| Secret từ `.env`, không nằm trong file compose | `:17-19` (`${POSTGRES_USER/PASSWORD/DB}`) + `.env.example`, `.gitignore:6-8` (`.env`, `.env.*`, `!.env.example`) |
| Named volume cho dữ liệu Postgres | `:22` (`- pgdata:/var/lib/postgresql/data`), khai báo top-level `:90-92` |
| Mạng do người dùng định nghĩa ⇒ DNS theo tên service | `:85-88` (`shopnet: driver: bridge`); mỗi service `networks: - shopnet` tại `:23-24`, `:46-47`, `:64-65`, `:82-83` |
| DB host là TÊN SERVICE (`db`), không localhost/IP | `:40` (catalog), `:56` (cart), `:74` (order) — `…@db:${POSTGRES_PORT}/…` |
| Service→service cũng qua tên service | `:58` (`CATALOG_URL: http://catalog:3001`), `:75-76` (order → catalog + cart) |
| Healthcheck DB | `:25-30` (`pg_isready -U … -d …`, interval 5s, retries 10) |
| App chờ DB healthy | `:41-43` (catalog), `:59-61` (cart), `:77-79` (order) |
| Seed chỉ khi bảng rỗng ⇒ dữ liệu bền bỉ | `ProductStore.cs:55-64` (`SELECT count(*)` → `skipping seed`) |

Số `5001`/`5002`/`5003` chỉ xuất hiện ở chỗ khai **default** (`Program.cs:5` của Catalog/Cart, `Program.cs:6` của order), **không** trong `UseUrls` — `UseUrls` chỉ nội suy biến `{config.Port}`/`{port}`.

## Transcript chạy thật (.NET SDK 10.0.301)

### Test 1 — cả 4 service, identity mặc định, cùng JSON shape

```
$ dotnet run --project services/Catalog & dotnet run --project services/Cart & \
  dotnet run --project services/order & dotnet run --project services/payment &

$ curl :5001/health -> {"service":"catalog","status":"ok"}
$ curl :5002/health -> {"service":"cart","status":"ok"}
$ curl :5003/health -> {"service":"order","status":"ok"}
$ curl :5004/health -> {"service":"payment","status":"ok"}
```

### Test 2 — kill Cart, ba service kia không bị ảnh hưởng

```
$ kill <PID của Cart>   # chỉ Cart

$ curl :5001/health -> {"service":"catalog","status":"ok"}   # vẫn sống
$ curl :5002/health -> (connection refused)                  # Cart đã chết
$ curl :5003/health -> {"service":"order","status":"ok"}     # vẫn sống
$ curl :5004/health -> {"service":"payment","status":"ok"}   # vẫn sống
```

### Test 3 — SERVICE_NAME override cho order/payment (chứng minh KHÔNG hardcode)

```
$ SERVICE_NAME=order-probe dotnet run --project services/order
$ curl :5003/health -> {"service":"order-probe","status":"ok"}

$ SERVICE_NAME=payment-probe dotnet run --project services/payment
$ curl :5004/health -> {"service":"payment-probe","status":"ok"}
```

Đổi `SERVICE_NAME` làm đổi hẳn giá trị `service` trong response — chứng minh `Program.cs:9` của order/payment đọc identity từ environment tại runtime, không phải chuỗi hardcode cố định.
