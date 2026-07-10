# StarCi Shop — Bản đồ Service

Monorepo .NET, mỗi service là một project độc lập trong một solution. Không có project "logic dùng chung".

- **Catalog** : Sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm. KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
- **Cart** : Sở hữu lựa chọn item đang dở của một khách (thêm / xóa / xem). KHÔNG đặt đơn hay thu tiền.
- **order** : Sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn. KHÔNG thu tiền thẻ.
- **payment** : Sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán. KHÔNG quản lý sản phẩm hay giỏ hàng.

## Bố cục

```
starci-shop.slnx              # solution gốc, tham chiếu 4 project service
services/
  Catalog/  Catalog.csproj  Program.cs  Config.cs
  Cart/     Cart.csproj     Program.cs  Config.cs
  order/    order.csproj    Program.cs
  payment/  payment.csproj  Program.cs
```

Mỗi service một `.csproj` riêng (`Microsoft.NET.Sdk.Web`, `net10.0`), build và chạy độc lập, không `ProjectReference` chéo.

## Config từ environment (Catalog, Cart)

Catalog và Cart đọc `PORT` và `SERVICE_NAME` từ environment qua `Config.Load(defaultPort, defaultName)` trong `Config.cs` của riêng mình — default riêng (Catalog `5001`/`catalog`, Cart `5002`/`cart`). `PORT` không phải số → ném `InvalidOperationException` ngay khi khởi động. `Program.cs` truyền `config.Port` vào `builder.WebHost.UseUrls(...)` (không hardcode cổng) và `config.ServiceName` vào log khởi động lẫn `/health`.

## Build

```bash
dotnet build
```

```
$ dotnet build
  Catalog -> .../services/Catalog/bin/Debug/net10.0/Catalog.dll
  Cart    -> .../services/Cart/bin/Debug/net10.0/Cart.dll
  order   -> .../services/order/bin/Debug/net10.0/order.dll
  payment -> .../services/payment/bin/Debug/net10.0/payment.dll
Build succeeded.  0 Warning(s)  0 Error(s)
```

Build cô lập một service (không kéo theo service khác):

```bash
dotnet build services/Catalog     # chỉ dựng Catalog
```

## Chạy từng service

```bash
dotnet run --project services/Catalog            # mặc định :5001
PORT=8080 dotnet run --project services/Catalog  # override cổng qua env
dotnet run --project services/Cart               # mặc định :5002
dotnet run --project services/order              # :5003
dotnet run --project services/payment            # :5004
```

Health check: `GET /health` → `{"service":"<tên>","status":"ok"}`.
