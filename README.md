# StarCi Shop — Bản đồ Service

Monorepo .NET chứa bốn microservice độc lập. Đây là khung cho các milestone sau (container, database, gateway, saga, flash sale) — mọi thứ cắm vào các thư mục `services/` bên dưới, không có service thứ năm gom logic dùng chung.

- **Catalog** : Sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm. KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
- **Cart** : Sở hữu lựa chọn item đang dở của một khách (thêm / xóa / xem). KHÔNG đặt đơn hay thu tiền.
- **order** : Sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn. KHÔNG thu tiền thẻ.
- **payment** : Sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán. KHÔNG quản lý sản phẩm hay giỏ hàng.

## Bố cục

```
starci-shop/                 # gốc monorepo
  README.md                  # bản đồ service (file này)
  starci-shop.slnx           # solution gốc, tham chiếu bốn project service
  services/
    Catalog/   Catalog.csproj   Config.cs   Program.cs
    Cart/      Cart.csproj      Config.cs   Program.cs
    order/     order.csproj                 Program.cs
    payment/   payment.csproj                Program.cs
```

Mỗi service là một `.csproj` độc lập — build và chạy riêng, không tham chiếu chéo lẫn nhau, không có project `Shared`/`Common` chứa business logic.

> Ghi chú casing: `Catalog` và `Cart` dùng tên thư mục/project PascalCase (khớp namespace C#: `namespace Catalog;`, `namespace Cart;`). `order` và `payment` hiện vẫn ở dạng cũ (lowercase, chưa có `Config.cs`) — chưa được nâng cấp lên cùng pattern đọc config từ env; đó là việc của milestone sau, không nằm trong phạm vi thay đổi này.

## Config từ environment (Catalog, Cart)

Catalog và Cart đọc `PORT` và `SERVICE_NAME` từ environment qua helper `Config.Load(defaultPort, defaultName)` (`services/Catalog/Config.cs`, `services/Cart/Config.cs`) — mỗi service có mặc định riêng (Catalog: port 5001 / tên "catalog"; Cart: port 5002 / tên "cart"). `PORT` không hợp lệ (không parse được thành số) sẽ ném `InvalidOperationException` ngay khi khởi động thay vì âm thầm dùng sai cổng.

## Build

Từ gốc repo:

```bash
dotnet build
```

Output thật (.NET SDK 10.0.301, sau khi đổi Catalog/Cart sang PascalCase + thêm Config.cs):

```
$ dotnet build
  Determining projects to restore...
  Restored E:\code\PetProject\services\payment\payment.csproj (in 89 ms).
  Restored E:\code\PetProject\services\order\order.csproj (in 89 ms).
  Restored E:\code\PetProject\services\Catalog\Catalog.csproj (in 89 ms).
  Restored E:\code\PetProject\services\Cart\Cart.csproj (in 89 ms).
  payment -> E:\code\PetProject\services\payment\bin\Debug\net10.0\payment.dll
  order -> E:\code\PetProject\services\order\bin\Debug\net10.0\order.dll
  Catalog -> E:\code\PetProject\services\Catalog\bin\Debug\net10.0\Catalog.dll
  Cart -> E:\code\PetProject\services\Cart\bin\Debug\net10.0\Cart.dll

Build succeeded.
    0 Warning(s)
    0 Error(s)

Time Elapsed 00:00:04.80
```

Build cô lập — `dotnet build services/Catalog` chỉ dựng Catalog, không đụng tới Cart:

```
$ dotnet build services/Catalog
  Determining projects to restore...
  Restored E:\code\PetProject\services\Catalog\Catalog.csproj (in 71 ms).
  Catalog -> E:\code\PetProject\services\Catalog\bin\Debug\net10.0\Catalog.dll

Build succeeded.
    0 Warning(s)
    0 Error(s)
```

(`services/Cart/bin` không tồn tại sau lệnh build này — Cart chưa từng được biên dịch.)

## Chạy từng service độc lập

```bash
PORT=5001 dotnet run --project services/Catalog   # http://localhost:5001/health
PORT=5002 dotnet run --project services/Cart      # http://localhost:5002/health
dotnet run --project services/order               # http://localhost:5003/health
dotnet run --project services/payment             # http://localhost:5004/health
```

Đã chạy thật cả Catalog (PORT=5001) và Cart (PORT=5002) song song, mỗi service in một dòng log khởi động và trả lời health check:

```
[catalog] listening on :5001
...
GET http://localhost:5001/health -> {"service":"catalog","status":"ok"}
GET http://localhost:5001/products -> [{"id":"sku-1","title":"Starter Mug","priceCents":1200}]

[cart] listening on :5002
...
GET http://localhost:5002/health -> {"service":"cart","status":"ok"}
POST http://localhost:5002/cart/items {"sku":"sku-1","qty":2} -> {"items":[{"sku":"sku-1","qty":2}]}
```

## Luật ranh giới

1. Không project `Shared`/`Common`/`Core` chứa business logic.
2. Không project nào `ProjectReference` sang project service khác.
3. Mỗi service build độc lập: `dotnet build services/<tên>/<tên>.csproj` phải thành công mà không cần build service khác trước.
4. Thêm service mới = thêm thư mục `services/<tên>` **và** `dotnet sln add` project đó vào `starci-shop.slnx`. Solution bỏ sót một project vẫn build được các project còn lại, nhưng service đó thành mồ côi — luôn `dotnet sln list` để xác nhận đủ bốn.

> Ghi chú: SDK 10 tạo file solution mới ở định dạng `.slnx` (XML) thay vì `.sln` cổ điển khi chạy `dotnet new sln`. `dotnet build`, `dotnet sln add/list` đều thao tác trên `.slnx` y hệt `.sln`.

> Ghi chú vận hành trên Windows: NTFS không phân biệt hoa/thường. Đổi tên thư mục/file chỉ khác case (`catalog` → `Catalog`) cần rename hai bước qua tên tạm (`mv catalog __tmp && mv __tmp Catalog`), vì `mv catalog Catalog` trực tiếp bị hiểu nhầm là "move vào chính nó". Ngoài ra MSBuild build-server (node reuse) có thể cache project theo path không phân biệt case — nếu build ra kết quả với casing cũ sau khi đổi tên, chạy `dotnet build-server shutdown` rồi xoá `bin/`/`obj/` và build lại.
