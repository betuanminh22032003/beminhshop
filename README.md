# StarCi Shop — Bản đồ Service

Monorepo .NET chứa bốn microservice độc lập. Đây là khung cho các milestone sau (container, database, gateway, saga, flash sale) — mọi thứ cắm vào các thư mục `services/` bên dưới, không có service thứ năm gom logic dùng chung.

- **catalog** : Sở hữu danh sách sản phẩm và đọc chi tiết sản phẩm. KHÔNG sở hữu giỏ hàng, đơn hàng, hay tiền.
- **cart** : Sở hữu lựa chọn item đang dở của một khách (thêm / xóa / xem). KHÔNG đặt đơn hay thu tiền.
- **order** : Sở hữu việc biến giỏ hàng thành đơn đã đặt và theo dõi vòng đời của đơn. KHÔNG thu tiền thẻ.
- **payment** : Sở hữu việc thu tiền cho một đơn và ghi lại kết quả thanh toán. KHÔNG quản lý sản phẩm hay giỏ hàng.

## Bố cục

```
starci-shop/                 # gốc monorepo
  README.md                  # bản đồ service (file này)
  starci-shop.slnx           # solution gốc, tham chiếu bốn project service
  services/
    catalog/   catalog.csproj   Program.cs
    cart/      cart.csproj      Program.cs
    order/     order.csproj     Program.cs
    payment/   payment.csproj   Program.cs
```

Mỗi service là một `.csproj` độc lập — build và chạy riêng, không tham chiếu chéo lẫn nhau, không có project `Shared`/`Common` chứa business logic.

## Build

Từ gốc repo:

```bash
dotnet build
```

Output thật (chạy từ gốc repo sau khi tạo bốn project và solution, .NET SDK 10.0.301):

```
$ dotnet build
  Determining projects to restore...
  All projects are up-to-date for restore.
  catalog -> E:\code\PetProject\services\catalog\bin\Debug\net10.0\catalog.dll
  payment -> E:\code\PetProject\services\payment\bin\Debug\net10.0\payment.dll
  order -> E:\code\PetProject\services\order\bin\Debug\net10.0\order.dll
  cart -> E:\code\PetProject\services\cart\bin\Debug\net10.0\cart.dll

Build succeeded.
    0 Warning(s)
    0 Error(s)

Time Elapsed 00:00:01.82
```

Cả bốn service build thành công, không lỗi.

## Chạy từng service độc lập

```bash
dotnet run --project services/catalog   # http://localhost:5001/health
dotnet run --project services/cart      # http://localhost:5002/health
dotnet run --project services/order     # http://localhost:5003/health
dotnet run --project services/payment   # http://localhost:5004/health
```

## Luật ranh giới

1. Không project `Shared`/`Common`/`Core` chứa business logic.
2. Không project nào `ProjectReference` sang project service khác.
3. Mỗi service build độc lập: `dotnet build services/<tên>/<tên>.csproj` phải thành công mà không cần build service khác trước.
4. Thêm service mới = thêm thư mục `services/<tên>` **và** `dotnet sln add` project đó vào `starci-shop.slnx`. Solution bỏ sót một project vẫn build được các project còn lại, nhưng service đó thành mồ côi — luôn `dotnet sln list` để xác nhận đủ bốn.

> Ghi chú: SDK 10 tạo file solution mới ở định dạng `.slnx` (XML) thay vì `.sln` cổ điển khi chạy `dotnet new sln`. `dotnet build`, `dotnet sln add/list` đều thao tác trên `.slnx` y hệt `.sln`.
