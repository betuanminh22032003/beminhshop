# StarCi Shop — Hướng dẫn cho AI agent

Monorepo .NET chứa **bốn microservice độc lập**: Catalog, Cart, order, payment. Đây là bộ khung cho các milestone sau (container, database, gateway, saga, flash sale) — mọi thay đổi phải cắm vào khung này, không phá nó.

## Bố cục

```
starci-shop.slnx        # solution gốc — GỌI TÊN cả 4 project service, không dùng glob
README.md               # bản đồ service — ĐỌC TRƯỚC khi sửa bất kỳ service nào
services/
  Catalog/               # sản phẩm         (mặc định http://localhost:5001, đọc PORT/SERVICE_NAME từ env)
  Cart/                  # giỏ hàng         (mặc định http://localhost:5002, đọc PORT/SERVICE_NAME từ env)
  order/                 # đơn hàng         (http://localhost:5003)
  payment/               # thanh toán       (http://localhost:5004)
```

Mỗi service: một `.csproj` (`Microsoft.NET.Sdk.Web`, `net10.0`) + `Program.cs` + `Properties/launchSettings.json` riêng. ASP.NET Core minimal API.

**Casing có chủ đích:** `Catalog`/`Cart` dùng PascalCase (thư mục, `.csproj`, namespace đều khớp `Catalog`/`Cart`) vì đã có `Config.cs` với `namespace Catalog;` / `namespace Cart;`. `order`/`payment` chưa được nâng cấp lên pattern này — đừng tự ý đổi tên chúng khi không có yêu cầu, và đừng "sửa cho đồng bộ" nếu task không nhắc tới.

**Config từ env (chỉ Catalog, Cart hiện tại):** đọc `PORT` và `SERVICE_NAME` qua `Config.Load(defaultPort, defaultName)` trong `Config.cs` của từng service — mỗi service tự định nghĩa `ServiceConfig`/`Config` của riêng mình (namespace khác nhau), KHÔNG factor ra project dùng chung. `PORT` không parse được thành số → ném lỗi ngay khi khởi động, không âm thầm fallback.

## Luật ranh giới (bất khả xâm phạm)

1. **Không tạo project "logic dùng chung".** Không `Shared`, `Common`, `Core`, `Libs` chứa business logic. Nếu hai service cần cùng một khái niệm, mỗi service tự định nghĩa phiên bản của mình.
2. **Service không `ProjectReference` sang service khác.** Không có tham chiếu project nào từ `services/A` sang `services/B`. Giao tiếp giữa service (khi milestone sau cần) đi qua HTTP API, không qua reference.
3. **Mỗi service build và chạy độc lập.** `dotnet build services/<tên>/<tên>.csproj` phải thành công mà không cần build service nào khác trước.
4. **Mỗi service sở hữu dữ liệu của nó.** Không đọc/ghi chéo dữ liệu. Chi tiết trách nhiệm từng service: [README.md](README.md).
5. **Thêm service mới = thêm thư mục `services/<tên>` VÀ `dotnet sln add` project đó vào `starci-shop.slnx`.** Solution bỏ sót một project vẫn build được các project còn lại nhưng service đó thành mồ côi — luôn kiểm tra bằng `dotnet sln list` sau khi thêm.

## Lệnh thường dùng

```bash
dotnet build                                  # build cả 4 service từ gốc
dotnet build services/Catalog                 # build 1 service độc lập (không kéo theo Cart)
PORT=5001 dotnet run --project services/Catalog  # chạy 1 service (health: GET /health)
dotnet sln list                               # xác nhận đủ 4 project được khai báo
```

Chạy dotnet ở **gốc repo** khi build/thao tác solution. Catalog/Cart lấy `PORT`/`SERVICE_NAME` từ env (mặc định 5001/"catalog" và 5002/"cart"); order/payment vẫn cố định theo `Properties/launchSettings.json` (5003/5004).

**Cảnh báo Windows (NTFS case-insensitive):** đổi tên chỉ khác hoa/thường (vd. `catalog` → `Catalog`) phải qua bước trung gian: `mv catalog __tmp && mv __tmp Catalog` — `mv catalog Catalog` trực tiếp báo lỗi "move vào chính nó". Sau khi đổi tên project, nếu `dotnet build` vẫn in ra path/AssemblyName casing cũ, đó là MSBuild build-server (node reuse) cache stale — chạy `dotnet build-server shutdown`, xoá `bin/`/`obj/`, rồi build lại.

## Quy ước khi sửa code

- Chưa chốt thư viện gì thêm ngoài ASP.NET Core minimal API có sẵn — đừng tự ý thêm EF Core, MediatR, AutoMapper... nếu task không yêu cầu.
- NuGet package mới khai báo trong `.csproj` **của service dùng nó**, không khai ở solution hay project khác.
- Sửa xong phải chứng minh: `dotnet build` (hoặc build riêng service bị sửa) thành công + `dotnet sln list` vẫn đủ 4 project. Với thay đổi runtime behavior (endpoint, config), chạy thật service (`dotnet run`) và gọi endpoint bằng `curl` — build/typecheck không xác nhận được hành vi lúc chạy.
- Cập nhật `README.md` khi (và chỉ khi) ranh giới trách nhiệm thay đổi — đó là quyết định lớn, nêu rõ với người dùng trước khi làm.
