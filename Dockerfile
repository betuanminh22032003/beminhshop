# Dockerfile đơn tầng cho service Catalog (.NET / ASP.NET Core).
# Build context = GỐC repo, vì Catalog tham chiếu packages/Shop.Contracts.
#   docker build -t starci-shop/catalog:dev .
# Cổng + URL DB đọc từ env LÚC CHẠY (PORT, CATALOG_DATABASE_URL) — không nướng vào image:
#   docker run -d --name catalog -p 3001:3001 \
#     -e PORT=3001 -e CATALOG_DATABASE_URL=postgres://catalog-db:5432/catalog starci-shop/catalog:dev
# (đơn tầng — thu nhỏ bằng multi-stage là task kế tiếp.)
FROM mcr.microsoft.com/dotnet/sdk:10.0

WORKDIR /src

# Chép contract dùng chung trước (Catalog phụ thuộc), rồi tới service.
COPY packages/Shop.Contracts/ packages/Shop.Contracts/
COPY services/Catalog/ services/Catalog/

RUN dotnet publish services/Catalog/Catalog.csproj -c Release -o /app

WORKDIR /app
ENTRYPOINT ["dotnet", "Catalog.dll"]
