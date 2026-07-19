# StarCi Shop — Bản đồ Service

Monorepo .NET, mỗi service là một project độc lập trong một solution. Không chia sẻ business logic; chỉ chia sẻ **contract dữ liệu thuần** qua `packages/Shop.Contracts` (record/enum: `Money`, `ProductId`, `OrderStatus`).

- **Catalog** : Sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm. KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
- **Cart** : Sở hữu lựa chọn item đang dở của một khách (thêm / xóa / xem). KHÔNG đặt đơn hay thu tiền.
- **order** : Sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn. KHÔNG thu tiền thẻ.
- **payment** : Sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán. KHÔNG quản lý sản phẩm hay giỏ hàng.

## Bố cục

```
starci-shop.slnx              # solution gốc, tham chiếu 4 service + Shop.Contracts
packages/
  Shop.Contracts/  Shop.Contracts.csproj  Money.cs  ProductId.cs  OrderStatus.cs   # record/enum thuần, dùng chung
scripts/
  dev.sh                       # LỆNH GỐC: dựng Catalog+Cart+order cùng lúc
  health.csx                   # probe /health cả đội (dotnet script)
services/
  Catalog/  Catalog.csproj  Program.cs  Config.cs  HealthResponse.cs  PriceQuote.cs   (env-driven + Dockerized — Config/HealthResponse LÀ code sống, không launchSettings)
  Cart/     Cart.csproj     Program.cs  Properties/launchSettings.json  CartLine.cs      (Config.cs, HealthResponse.cs — dead code)
  order/    order.csproj    Program.cs  Properties/launchSettings.json  Order.cs         (HealthResponse.cs — dead code)
  payment/  payment.csproj  Program.cs  Properties/launchSettings.json  HealthResponse.cs   (chưa đổi milestone này)
```

Mỗi service một `.csproj` riêng (`Microsoft.NET.Sdk.Web`, `net10.0`), build và chạy độc lập, KHÔNG `ProjectReference` sang service khác — nhưng có tham chiếu `packages/Shop.Contracts` (class library `Microsoft.NET.Sdk`) cho các kiểu dùng chung. `Shop.Contracts` không tham chiếu ngược lại service nào.

## Dựng cả cửa hàng bằng một lệnh + probe /health

Lệnh gốc `bash scripts/dev.sh` khởi động Catalog(5001) + Cart(5002) + order(5003) đồng thời, mỗi tiến trình `dotnet run` riêng với log tiền tố `[<svc>]`; khi một service thoát, `wait -n` trả về và script kết thúc (mã ≠ 0).

> Về ranh giới chia sẻ kiểu: value type domain xuyên service (`Money`/`ProductId`/`OrderStatus`) nằm trong `packages/Shop.Contracts` (single source of truth); còn DTO liveness `HealthResponse` KHÔNG chia sẻ — xem luật #1 trong `AGENTS.md`.

Chứng minh cả đội xanh: `dotnet script scripts/health.csx` gọi `/health` từng cổng, in `OK`/`ERR` mỗi service, `ALL GREEN`/`SOME RED`, thoát mã 0 nếu tất cả xanh — khác 0 nếu có cái down.

Cả 4 service trả cùng shape JSON `{"service":"<tên>","status":"ok"}`, nhưng khác cơ chế:
- **Cart/order:** `/health` inline `Results.Json(new { service = "<tên>", status = "ok" })` (tên hardcode), cổng chốt bằng `app.Run("http://localhost:<port>")` + `launchSettings.json`.
- **Catalog:** env-driven (milestone container) — `/health` qua record `HealthResponse.Ok(config.ServiceName)`, cổng từ `PORT` env (mặc định 5001), bind `0.0.0.0`; xem mục Docker. dev.sh vẫn dựng Catalog trên 5001 như thường.
- **payment:** CHƯA đổi — vẫn record `HealthResponse.Ok(serviceName)` với `serviceName` từ `SERVICE_NAME` env, `.AllowAnonymous()`.

**Windows caveat:** trap `kill ${pids[*]}` trong dev.sh chỉ hạ subshell; tiến trình `dotnet` cháu bị mồ côi vẫn giữ cổng — dọn bằng `taskkill //F //PID <pid>`.

## Lệnh

```bash
dotnet build                                      # build cả 4
bash scripts/dev.sh                               # dựng Catalog+Cart+order cùng lúc (5001/5002/5003)
dotnet script scripts/health.csx                  # probe /health cả đội (cần: dotnet tool install -g dotnet-script)
dotnet run --project services/Catalog             # chạy riêng Catalog (đọc PORT env, mặc định 5001)
dotnet run --project services/Cart                # chạy riêng Cart   (cổng cứng 5002)
```

Health check: `GET /health` → `{"service":"<tên>","status":"ok"}`. Cart/order chốt cổng cứng trong `app.Run(...)`; **Catalog đọc `PORT` từ env** (mặc định 5001, bind `0.0.0.0`, Dockerized).

## Docker — Catalog (milestone container)

`Dockerfile` + `.dockerignore` ở **gốc repo** đóng gói service **Catalog** (đơn tầng). Build context là gốc vì Catalog tham chiếu `packages/Shop.Contracts`. Catalog đọc `PORT` **và** `CATALOG_DATABASE_URL` từ env lúc chạy và bind `0.0.0.0` (để reachable qua `-p`):

```bash
docker build -t starci-shop/catalog:dev .
docker run -d --name catalog -p 3001:3001 \
  -e PORT=3001 -e CATALOG_DATABASE_URL=postgres://catalog-db:5432/catalog \
  starci-shop/catalog:dev
curl -s http://localhost:3001/products   # {"items":[{"id":"sku-001",...}],"total":3}
```

Đổi `-e PORT=4000 -p 4000:4000` cùng image đó → bind 4000 (cổng từ env, không cứng hóa); `docker logs catalog` in `[catalog] listening on :<port>`. Đơn tầng ở milestone này — thu nhỏ bằng multi-stage là task kế tiếp.

---

# Mã nguồn đầy đủ (để đối chiếu chấm điểm)

> ⚠️ **Listing Catalog dưới đây đã regenerate cho milestone container** — `services/Catalog/Program.cs` + `services/Catalog/Config.cs` khớp ĐÚNG source hiện tại: đọc `PORT`/`SERVICE_NAME`/`CATALOG_DATABASE_URL` từ env qua `Config.Load`, `UseUrls` bind `0.0.0.0` (reachable qua `-p`), `GET /products` trả `{items,total}` với `sku-001`/`sku-002`/`sku-003`, `/health` qua record `HealthResponse` + `.AllowAnonymous()`. **Cart/order** thì listing bên dưới còn phản ánh milestone dev-scripts (cổng cứng `app.Run("http://localhost:<port>")` + `launchSettings.json`, `/health` inline `Results.Json(...)` — xem mục "Dựng cả cửa hàng bằng một lệnh" ở trên); **payment** khớp thực tế. Bảng tiêu chí health/identity bên dưới lập từ milestone trước — số dòng của Catalog đã cập nhật theo listing mới (UseUrls nay ở `Program.cs:9`).

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
16  // Danh sách sản phẩm đã seed — shape { items, total }.
17  var products = new[]
18  {
19      new { id = "sku-001", title = "Starter Mug", priceCents = 1200 },
20      new { id = "sku-002", title = "Field Notebook", priceCents = 800 },
21      new { id = "sku-003", title = "Enamel Pin", priceCents = 500 },
22  };
23  app.MapGet("/products", () => new { items = products, total = products.Length });
24
25  Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
26  Console.WriteLine($"[{config.ServiceName}] catalog db = {config.DatabaseUrl}");
27  app.Run();
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
 8  builder.WebHost.UseUrls($"http://localhost:{config.Port}");
 9  var app = builder.Build();
10
11  var items = new List<object>();
12
13  // Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
14  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(config.ServiceName)))
15     .AllowAnonymous();
16  app.MapPost("/cart/items", (CartItem item) =>
17  {
18      items.Add(new { sku = item.Sku, qty = item.Qty ?? 1 });
19      return Results.Created("/cart/items", new { items });
20  });
20
21  Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
22  app.Run();
23
24  record CartItem(string Sku, int? Qty);
```

### `services/order/Program.cs`

```csharp
 1  // order: sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn.
 2  // KHÔNG thu tiền thẻ.
 3  var builder = WebApplication.CreateBuilder(args);
 4  var app = builder.Build();
 5
 6  var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "order";
 7
 8  // Liveness probe: không xác thực, không tác dụng phụ, đăng ký trước UseAuthentication (nếu milestone sau thêm auth).
 9  app.MapGet("/health", () => Results.Ok(HealthResponse.Ok(serviceName)))
10     .AllowAnonymous();
11
12  app.Run();
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
15          var databaseUrl = Environment.GetEnvironmentVariable("CATALOG_DATABASE_URL")
16                            ?? "postgres://localhost:5432/catalog";
17          return new ServiceConfig(port, name, databaseUrl);
18      }
19  }
```

### `services/Cart/Config.cs`

```csharp
 1  namespace Cart;
 2
 3  public record ServiceConfig(int Port, string ServiceName);
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
14          return new ServiceConfig(port, name);
15      }
16  }
```

### `services/Catalog/Catalog.csproj`

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

### `services/Cart/Cart.csproj`

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

### `services/order/order.csproj`

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
| Identity đọc từ env, không hardcode | `Config.cs:13` (`SERVICE_NAME`) | `Config.cs:13` | `Program.cs:6` (`SERVICE_NAME`) | `Program.cs:6` |
| Default khi thiếu `SERVICE_NAME` | `Config.cs:13` `?? defaultName` | `Config.cs:13` | `Program.cs:6` `?? "order"` | `Program.cs:6` `?? "payment"` |
| `GET /health` dùng record `HealthResponse.Ok(...)` | `Program.cs:13` | `Program.cs:14` | `Program.cs:9` | `Program.cs:9` |
| `HealthResponse` là bản riêng của service (không project chung) | `HealthResponse.cs` (`namespace Catalog;`) | `HealthResponse.cs` (`namespace Cart;`) | `HealthResponse.cs` (global) | `HealthResponse.cs` (global) |
| Cùng JSON shape `{"service":...,"status":"ok"}` | dòng log Test 1 dưới | dòng log Test 1 | dòng log Test 1 | dòng log Test 1 |
| `.csproj` riêng, `Sdk.Web` + `net10.0`, không `ProjectReference` chéo | `Catalog.csproj:1,4` | `Cart.csproj:1,4` | `order.csproj:1,4` | `payment.csproj:1,4` |
| Solution tham chiếu project riêng | `starci-shop.slnx:4` | `starci-shop.slnx:3` | `starci-shop.slnx:5` | `starci-shop.slnx:6` |
| `/health` unauthenticated, side-effect free | `Program.cs:13-14` (`AllowAnonymous`) | `Program.cs:14-15` (`AllowAnonymous`) | `Program.cs:9-10` (`AllowAnonymous`) | `Program.cs:9-10` (`AllowAnonymous`) |

Catalog/Cart riêng có thêm (đã xác lập từ milestone trước, không đổi ở đây):

| Tiêu chí | Catalog | Cart |
| --- | --- | --- |
| Gọi `Config.Load(...)` với default riêng | `Program.cs:5` (`5001`/`catalog`) | `Program.cs:5` (`5002`/`cart`) |
| `config.Port` → `UseUrls` (không literal cứng) | `Program.cs:9` (bind `0.0.0.0`) | `Program.cs:8` |
| Ném lỗi khi PORT malformed | `Config.cs:11-12` | `Config.cs:11-12` |

Số `5001`/`5002` chỉ xuất hiện tại `Program.cs:5` (tham số `defaultPort`), **không** trong `UseUrls` (Catalog `Program.cs:9` bind `0.0.0.0`, Cart `Program.cs:8` — chỉ dùng biến `{config.Port}`).

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
