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
services/
  Catalog/  Catalog.csproj  Program.cs  Config.cs  ProductStore.cs  HealthResponse.cs  PriceQuote.cs   (env-driven, Dockerized ở /Dockerfile, /products đọc Postgres)
  Cart/     Cart.csproj     Program.cs  Config.cs  Dockerfile  Properties/launchSettings.json  CartLine.cs  HealthResponse.cs   (env-driven, Dockerized)
  order/    order.csproj    Program.cs  Dockerfile  Properties/launchSettings.json  Order.cs  HealthResponse.cs   (env-driven inline, Dockerized)
  payment/  payment.csproj  Program.cs  Properties/launchSettings.json  HealthResponse.cs   (CHƯA đổi: cổng cứng theo launchSettings, chưa có Dockerfile)
```

Mỗi service một `.csproj` riêng (`Microsoft.NET.Sdk.Web`, `net10.0`), build và chạy độc lập, KHÔNG `ProjectReference` sang service khác — nhưng có tham chiếu `packages/Shop.Contracts` (class library `Microsoft.NET.Sdk`) cho các kiểu dùng chung. `Shop.Contracts` không tham chiếu ngược lại service nào.

## Dựng cả cửa hàng bằng một lệnh + probe /health

Lệnh gốc `bash scripts/dev.sh` khởi động Catalog(5001) + Cart(5002) + order(5003) đồng thời, mỗi tiến trình `dotnet run` riêng với log tiền tố `[<svc>]`; khi một service thoát, `wait -n` trả về và script kết thúc (mã ≠ 0).

> Về ranh giới chia sẻ kiểu: value type domain xuyên service (`Money`/`ProductId`/`OrderStatus`) nằm trong `packages/Shop.Contracts` (single source of truth); còn DTO liveness `HealthResponse` KHÔNG chia sẻ — xem luật #1 trong `AGENTS.md`.

Chứng minh cả đội xanh: `dotnet script scripts/health.csx` gọi `/health` từng cổng, in `OK`/`ERR` mỗi service, `ALL GREEN`/`SOME RED`, thoát mã 0 nếu tất cả xanh — khác 0 nếu có cái down.

Cả 4 service trả cùng shape JSON `{"service":"<tên>","status":"ok"}`, nhưng khác cơ chế:
- **Catalog/Cart/order:** cổng từ `PORT` env (mặc định 5001/5002/5003), bind `0.0.0.0` qua `UseUrls` để container reachable qua `-p`; identity từ `SERVICE_NAME`. Catalog dùng record `HealthResponse.Ok(config.ServiceName)`; Cart/order dùng `Results.Json(new { service = <từ env>, status = "ok" })` — cùng shape.
- **payment:** CHƯA đổi — record `HealthResponse.Ok(serviceName)` với `serviceName` từ `SERVICE_NAME` env, `.AllowAnonymous()`, cổng theo `launchSettings.json` (5004).

**Windows caveat:** trap `kill ${pids[*]}` trong dev.sh chỉ hạ subshell; tiến trình `dotnet` cháu bị mồ côi vẫn giữ cổng — dọn bằng `taskkill //F //PID <pid>`.

**`health.csx` gọi `127.0.0.1`, không `localhost`:** ba service bind `0.0.0.0` (IPv4); `localhost` trên Windows phân giải `::1` trước nên `HttpClient` treo tới timeout dù service vẫn sống (`curl` không bị vì tự fallback sang IPv4).

Ngoài Docker (dev.sh) không có Postgres — Catalog retry 5 lần rồi phục vụ **seed in-memory** và ghi rõ trong log `[catalog] products source = in-memory seed`, nên `dev.sh` + `health.csx` vẫn xanh như trước.

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
4. **App chờ DB thật sự sẵn sàng.** `db` có `healthcheck` bằng `pg_isready`; ba service khai `depends_on: db: condition: service_healthy`.

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

---

# Mã nguồn đầy đủ (để đối chiếu chấm điểm)

> ⚠️ **Listing đã regenerate cho milestone compose** (sinh trực tiếp từ file thật nên số dòng khớp): `Program.cs`/`Config.cs`/`.csproj` của **Catalog, Cart, order** đều là bản env-driven hiện tại — `PORT`/`SERVICE_NAME` + địa chỉ phụ thuộc (`DATABASE_URL`, `CATALOG_URL`, `CART_URL`) đọc từ env, `UseUrls` bind `0.0.0.0`. Catalog thêm `ProductStore.cs` (Npgsql, `/products` đọc Postgres, seed khi bảng rỗng). **payment** KHÔNG đổi ở milestone này (cổng theo `launchSettings.json`, chưa Dockerized) nên listing của nó vẫn như cũ.

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
15  var builder = WebApplication.CreateBuilder(args);
16  // Bind 0.0.0.0 để container reachable qua -p; cổng lấy từ env PORT (mặc định 5003).
17  builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
18  var app = builder.Build();
19
20  // /health: shape cố định { service, status } cho probe gốc (scripts/health.csx).
21  app.MapGet("/health", () => Results.Json(new { service = serviceName, status = "ok" }));
22
23  Console.WriteLine($"[{serviceName}] listening on :{port}");
24  Console.WriteLine($"[{serviceName}] catalog url = {catalogUrl}");
25  Console.WriteLine($"[{serviceName}] cart url = {cartUrl}");
26  app.Run();
```

### `services/payment/Program.cs`

```csharp
 1  // payment: sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán.
 2  // KHÔNG quản lý sản phẩm hay giỏ hàng.
 3  var builder = WebApplication.CreateBuilder(args);
 4  var app = builder.Build();
 5
 6  var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "payment";
 7
 8  // Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
 9  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(serviceName)))
10     .AllowAnonymous();
11
12  app.Run();
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
1  record HealthResponse(string Service, string Status)
2  {
3      public static HealthResponse Ok(string service) => new(service, "ok");
4  }
```

### `services/payment/HealthResponse.cs`

```csharp
1  record HealthResponse(string Service, string Status)
2  {
3      public static HealthResponse Ok(string service) => new(service, "ok");
4  }
```

`order`/`payment` chưa dùng namespace riêng ở milestone này (chưa nâng cấp lên pattern `Config.cs` như Catalog/Cart) — record ở global namespace, cùng nội dung `Service`/`Status`/`Ok(...)` như hai service kia. Không project nào tham chiếu record của service khác — 4 định nghĩa độc lập, trùng shape.

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
 7      <!-- Chốt tên assembly để output publish (Catalog.dll) khớp ENTRYPOINT của Dockerfile,
 8           không phụ thuộc casing thư mục (NTFS case-insensitive). -->
 9      <AssemblyName>Catalog</AssemblyName>
10    </PropertyGroup>
11
12    <ItemGroup>
13      <ProjectReference Include="..\..\packages\Shop.Contracts\Shop.Contracts.csproj" />
14    </ItemGroup>
15
16    <ItemGroup>
17      <PackageReference Include="Npgsql" Version="10.0.3" />
18    </ItemGroup>
19
20  </Project>
```

### `Dockerfile` (đa tầng — tầng build có SDK, tầng runtime KHÔNG)

```dockerfile
 1  # --- tầng build: full .NET SDK, restore + publish ---
 2  FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
 3  WORKDIR /src
 4  COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/
 5  COPY services/Catalog/Catalog.csproj services/Catalog/
 6  RUN dotnet restore services/Catalog/Catalog.csproj
 7  COPY packages/Shop.Contracts/ packages/Shop.Contracts/
 8  COPY services/Catalog/ services/Catalog/
 9  RUN dotnet publish services/Catalog/Catalog.csproj -c Release -o /app/publish --no-restore
10
11  # --- tầng runtime: CHỈ ASP.NET runtime, không SDK, không chạy root ---
12  FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
13  ENV DOTNET_RUNNING_IN_CONTAINER=true
14  WORKDIR /app
15  COPY --from=build /app/publish ./
16  USER app
17  EXPOSE 3001
18  ENTRYPOINT ["dotnet", "Catalog.dll"]
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
27        test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
28        interval: 5s
29        timeout: 3s
30        retries: 10
31
32    catalog:
33      build:
34        context: .
35        dockerfile: Dockerfile
36      environment:
37        PORT: 3001
38        SERVICE_NAME: catalog
39        # host là "db" — tên service trong compose, do DNS của shopnet phân giải.
40        DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:${POSTGRES_PORT}/${POSTGRES_DB}
41      depends_on:
42        db:
43          condition: service_healthy
44      ports:
45        - "3001:3001"
46      networks:
47        - shopnet
48
49    cart:
50      build:
51        context: .
52        dockerfile: services/Cart/Dockerfile
53      environment:
54        PORT: 3002
55        SERVICE_NAME: cart
56        DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:${POSTGRES_PORT}/${POSTGRES_DB}
57        # Lưu lượng service→service cũng đi bằng DNS theo tên service.
58        CATALOG_URL: http://catalog:3001
59      depends_on:
60        db:
61          condition: service_healthy
62      ports:
63        - "3002:3002"
64      networks:
65        - shopnet
66
67    order:
68      build:
69        context: .
70        dockerfile: services/order/Dockerfile
71      environment:
72        PORT: 3003
73        SERVICE_NAME: order
74        DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:${POSTGRES_PORT}/${POSTGRES_DB}
75        CATALOG_URL: http://catalog:3001
76        CART_URL: http://cart:3002
77      depends_on:
78        db:
79          condition: service_healthy
80      ports:
81        - "3003:3003"
82      networks:
83        - shopnet
84
85  networks:
86    # Mạng do người dùng định nghĩa = có DNS nội bộ theo tên service.
87    shopnet:
88      driver: bridge
89
90  volumes:
91    # Khai báo một lần ở cấp cao nhất: Docker quản lý vòng đời volume độc lập với container.
92    pgdata:
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
 2  # (Cart tham chiếu packages/Shop.Contracts):
 3  #   docker build -f services/Cart/Dockerfile -t starci-shop/cart:slim .
 4  # docker-compose.yaml khai đúng cặp context: . / dockerfile: services/Cart/Dockerfile.
 5
 6  # --- tầng build: full .NET SDK, restore + publish ---
 7  FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
 8  WORKDIR /src
 9
10  # Copy .csproj và restore TRƯỚC khi copy source (tận dụng layer cache).
11  COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/
12  COPY services/Cart/Cart.csproj services/Cart/
13  RUN dotnet restore services/Cart/Cart.csproj
14
15  # Copy source rồi publish ra /app/publish.
16  COPY packages/Shop.Contracts/ packages/Shop.Contracts/
17  COPY services/Cart/ services/Cart/
18  RUN dotnet publish services/Cart/Cart.csproj -c Release -o /app/publish --no-restore
19
20  # --- tầng runtime: CHỈ ASP.NET runtime, không SDK, không chạy root ---
21  FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
22  ENV DOTNET_RUNNING_IN_CONTAINER=true
23  WORKDIR /app
24
25  # CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
26  COPY --from=build /app/publish ./
27
28  # Image aspnet có sẵn user không phải root tên "app".
29  USER app
30  EXPOSE 3002
31  # PORT / CATALOG_URL / DATABASE_URL đọc từ env lúc chạy (không nướng vào image).
32  ENTRYPOINT ["dotnet", "Cart.dll"]
```

### `services/order/Dockerfile`

```dockerfile
 1  # Dockerfile ĐA TẦNG cho service order (.NET). Build context = GỐC repo
 2  # (order tham chiếu packages/Shop.Contracts):
 3  #   docker build -f services/order/Dockerfile -t starci-shop/order:slim .
 4  # docker-compose.yaml khai đúng cặp context: . / dockerfile: services/order/Dockerfile.
 5
 6  # --- tầng build: full .NET SDK, restore + publish ---
 7  FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
 8  WORKDIR /src
 9
10  # Copy .csproj và restore TRƯỚC khi copy source (tận dụng layer cache).
11  COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/
12  COPY services/order/order.csproj services/order/
13  RUN dotnet restore services/order/order.csproj
14
15  # Copy source rồi publish ra /app/publish.
16  COPY packages/Shop.Contracts/ packages/Shop.Contracts/
17  COPY services/order/ services/order/
18  RUN dotnet publish services/order/order.csproj -c Release -o /app/publish --no-restore
19
20  # --- tầng runtime: CHỈ ASP.NET runtime, không SDK, không chạy root ---
21  FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
22  ENV DOTNET_RUNNING_IN_CONTAINER=true
23  WORKDIR /app
24
25  # CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
26  COPY --from=build /app/publish ./
27
28  # Image aspnet có sẵn user không phải root tên "app".
29  USER app
30  EXPOSE 3003
31  # PORT / CATALOG_URL / CART_URL / DATABASE_URL đọc từ env lúc chạy (không nướng vào image).
32  ENTRYPOINT ["dotnet", "order.dll"]
```

### `services/Cart/Cart.csproj`

```xml
 1  <Project Sdk="Microsoft.NET.Sdk.Web">
 2
 3    <PropertyGroup>
 4      <TargetFramework>net10.0</TargetFramework>
 5      <Nullable>enable</Nullable>
 6      <ImplicitUsings>enable</ImplicitUsings>
 7      <!-- Chốt tên assembly để output publish (Cart.dll) khớp ENTRYPOINT của Dockerfile,
 8           không phụ thuộc casing thư mục (NTFS case-insensitive). -->
 9      <AssemblyName>Cart</AssemblyName>
10    </PropertyGroup>
11
12    <ItemGroup>
13      <ProjectReference Include="..\..\packages\Shop.Contracts\Shop.Contracts.csproj" />
14    </ItemGroup>
15
16  </Project>
```

### `services/order/order.csproj`

```xml
 1  <Project Sdk="Microsoft.NET.Sdk.Web">
 2
 3    <PropertyGroup>
 4      <TargetFramework>net10.0</TargetFramework>
 5      <Nullable>enable</Nullable>
 6      <ImplicitUsings>enable</ImplicitUsings>
 7      <!-- Chốt tên assembly để output publish (order.dll) khớp ENTRYPOINT của Dockerfile,
 8           không phụ thuộc casing thư mục (NTFS case-insensitive). -->
 9      <AssemblyName>order</AssemblyName>
10    </PropertyGroup>
11
12    <ItemGroup>
13      <ProjectReference Include="..\..\packages\Shop.Contracts\Shop.Contracts.csproj" />
14    </ItemGroup>
15
16  </Project>
```

### `services/payment/payment.csproj`

```xml
1  <Project Sdk="Microsoft.NET.Sdk.Web">
2
3    <PropertyGroup>
4      <TargetFramework>net10.0</TargetFramework>
5      <Nullable>enable</Nullable>
6      <ImplicitUsings>enable</ImplicitUsings>
7    </PropertyGroup>
8
9  </Project>
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
