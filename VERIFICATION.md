# Bằng chứng — Catalog & Cart đọc PORT/SERVICE_NAME từ env, không hardcode

Tài liệu này trích dẫn **trực tiếp source files** (nguyên văn, kèm số dòng) cho **cả hai**
service, cộng với kiểm tra cơ học tái lập được và transcript chạy thật. Chạy lại toàn bộ
phần kiểm tra tĩnh bằng: `bash verify.sh` (repo gốc).

---

## 1. Trích dẫn source trực tiếp

### `services/Catalog/Program.cs` (nguyên văn)

```csharp
 1  // catalog: sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm.
 2  // KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
 3  using Catalog;
 4
 5  var config = Config.Load(defaultPort: 5001, defaultName: "catalog");
 6
 7  var builder = WebApplication.CreateBuilder(args);
 8  builder.WebHost.UseUrls($"http://localhost:{config.Port}");
 9  var app = builder.Build();
10
11  app.MapGet("/health", () => new { service = config.ServiceName, status = "ok" });
12  app.MapGet("/products", () => new[] { new { id = "sku-1", title = "Starter Mug", priceCents = 1200 } });
13
14  Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
15  app.Run();
```

### `services/Cart/Program.cs` (nguyên văn) — **trích dẫn trực tiếp, không "giống hệt"**

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
13  app.MapGet("/health", () => new { service = config.ServiceName, status = "ok" });
14  app.MapPost("/cart/items", (CartItem item) =>
15  {
16      items.Add(new { sku = item.Sku, qty = item.Qty ?? 1 });
17      return Results.Created("/cart/items", new { items });
18  });
19
20  Console.WriteLine($"[{config.ServiceName}] listening on :{config.Port}");
21  app.Run();
22
23  record CartItem(string Sku, int? Qty);
```

### `services/Catalog/Config.cs` và `services/Cart/Config.cs`

Hai file **giống nhau về logic nhưng namespace khác nhau** (`namespace Catalog;` vs
`namespace Cart;`) — mỗi service tự mang bản của mình, KHÔNG có project/literal dùng chung:

```csharp
namespace Catalog;   // <-- Cart/Config.cs: "namespace Cart;"

public record ServiceConfig(int Port, string ServiceName);

public static class Config
{
    public static ServiceConfig Load(int defaultPort, string defaultName)
    {
        var rawPort = Environment.GetEnvironmentVariable("PORT");
        int port = defaultPort;
        if (!string.IsNullOrEmpty(rawPort) && !int.TryParse(rawPort, out port))
            throw new InvalidOperationException($"Invalid PORT=\"{rawPort}\": expected a number");
        var name = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? defaultName;
        return new ServiceConfig(port, name);
    }
}
```

### Đối chiếu từng yêu cầu → dòng code (cả hai file)

| Yêu cầu | Catalog/Program.cs | Cart/Program.cs |
| --- | --- | --- |
| Gọi `Config.Load(...)` | dòng 5 | dòng 5 |
| Đọc env, có default riêng | `defaultPort: 5001, "catalog"` | `defaultPort: 5002, "cart"` |
| `config.Port` → `UseUrls` (không literal) | dòng 8 | dòng 8 |
| `config.ServiceName` → log khởi động | dòng 14 | dòng 20 |
| `config.ServiceName` → `/health` | dòng 11 | dòng 13 |

---

## 2. Kiểm tra cơ học (chạy `bash verify.sh` — output thật)

```
== Catalog & Cart: entrypoint đọc env qua Config.Load, không hardcode cổng ==
PASS  Catalog/Program.cs: gọi Config.Load(...)
PASS  Catalog/Program.cs: UseUrls dùng biến config.Port
PASS  Catalog/Program.cs: UseUrls KHÔNG chứa số cứng
PASS  Catalog/Program.cs: log/health dùng config.ServiceName
PASS  Catalog/Config.cs: đọc PORT từ environment
PASS  Catalog/Config.cs: đọc SERVICE_NAME từ environment
PASS  Catalog/Config.cs: ném lỗi khi PORT không parse được
PASS  Catalog/Config.cs: namespace riêng (Catalog)
PASS  Cart/Program.cs: gọi Config.Load(...)
PASS  Cart/Program.cs: UseUrls dùng biến config.Port
PASS  Cart/Program.cs: UseUrls KHÔNG chứa số cứng
PASS  Cart/Program.cs: log/health dùng config.ServiceName
PASS  Cart/Config.cs: đọc PORT từ environment
PASS  Cart/Config.cs: đọc SERVICE_NAME từ environment
PASS  Cart/Config.cs: ném lỗi khi PORT không parse được
PASS  Cart/Config.cs: namespace riêng (Cart)

== Ranh giới: mỗi service độc lập, không dùng chung logic ==
PASS  Không ProjectReference chéo giữa Catalog/Cart
PASS  Không có thư mục service dùng chung (shared/common/core/libs)

==> TẤT CẢ PASS   (exit 0)
```

**Bằng chứng "không hardcode" quan trọng nhất** — số `5001`/`5002` chỉ xuất hiện đúng MỘT chỗ
trong mỗi file (tham số `defaultPort` của `Config.Load`), tuyệt đối không có trong `UseUrls`:

```
$ grep -HnE "5001|5002" services/Catalog/Program.cs services/Cart/Program.cs
services/Catalog/Program.cs:5:var config = Config.Load(defaultPort: 5001, defaultName: "catalog");
services/Cart/Program.cs:5:var config = Config.Load(defaultPort: 5002, defaultName: "cart");

$ grep -HnE 'UseUrls\(.*[0-9]' services/Catalog/Program.cs services/Cart/Program.cs
(không có kết quả — không dòng UseUrls nào chứa chữ số)
```

---

## 3. Transcript chạy thật (.NET SDK 10.0.301)

Nếu cổng bị hardcode, đặt `PORT=6100`/`6200` sẽ không làm dịch cổng. Ở đây nó dịch đúng, và
cổng mặc định KHÔNG bind — chứng minh cổng runtime đến 100% từ env qua `config.Port`.

```
### CATALOG ###
[default]
[catalog] listening on :5001
  health(:5001) -> {"service":"catalog","status":"ok"}
[PORT=6100 SERVICE_NAME=catalog-probe]
[catalog-probe] listening on :6100
  health(:6100) -> {"service":"catalog-probe","status":"ok"}
  default :5001 sau khi set env -> (refused, đúng)
[PORT=abc]
Unhandled exception. System.InvalidOperationException: Invalid PORT="abc": expected a number

### CART ###
[default]
[cart] listening on :5002
  health(:5002) -> {"service":"cart","status":"ok"}
  POST :5002/cart/items -> {"items":[{"sku":"sku-1","qty":2}]}
[PORT=6200 SERVICE_NAME=cart-probe]
[cart-probe] listening on :6200
  health(:6200) -> {"service":"cart-probe","status":"ok"}
[PORT=xyz]
Unhandled exception. System.InvalidOperationException: Invalid PORT="xyz": expected a number
```

---

## 4. Tách project & build cô lập

```
$ dotnet build-server shutdown && rm -rf services/*/bin services/*/obj
$ dotnet build services/Catalog
  Catalog -> E:\code\PetProject\services\Catalog\bin\Debug\net10.0\Catalog.dll
  Build succeeded.  0 Warning(s)  0 Error(s)
$ ls services/Cart/bin
ls: cannot access 'services/Cart/bin': No such file or directory   # Cart KHÔNG bị biên dịch
```

`dotnet sln list` → `Cart.csproj`, `Catalog.csproj`, `order.csproj`, `payment.csproj` (đủ 4,
mỗi cái một `.csproj` riêng, không `ProjectReference` chéo).
