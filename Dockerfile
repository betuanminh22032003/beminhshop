# Dockerfile đơn tầng cho service Catalog (.NET / ASP.NET Core).
# Build context = GỐC repo, vì Catalog tham chiếu packages/Shop.Contracts.
#   docker build -t starci-shop/catalog:dev .
# Cổng + URL DB đọc từ env LÚC CHẠY (PORT, CATALOG_DATABASE_URL) — không nướng vào image:
#   docker run -d --name catalog -p 3001:3001 \
#     -e PORT=3001 -e CATALOG_DATABASE_URL=postgres://catalog-db:5432/catalog starci-shop/catalog:dev
# (đơn tầng — thu nhỏ bằng multi-stage là task kế tiếp.)
FROM mcr.microsoft.com/dotnet/sdk:10.0

WORKDIR /src

# 1) Chép TRƯỚC các .csproj rồi restore — layer này chỉ chạy lại khi .csproj đổi,
#    tận dụng cache của Docker (không phải restore lại mỗi lần sửa source).
COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/
COPY services/Catalog/Catalog.csproj services/Catalog/
RUN dotnet restore services/Catalog/Catalog.csproj

# 2) Chép toàn bộ source rồi publish ra /app (đã restore ở trên → --no-restore).
COPY packages/Shop.Contracts/ packages/Shop.Contracts/
COPY services/Catalog/ services/Catalog/
RUN dotnet publish services/Catalog/Catalog.csproj -c Release -o /app --no-restore

# 3) Chạy assembly đã publish. AssemblyName mặc định = tên project → Catalog.dll trong /app.
WORKDIR /app
ENTRYPOINT ["dotnet", "Catalog.dll"]
