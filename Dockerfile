# Dockerfile đơn tầng cho service Catalog (.NET). Build context = GỐC repo
# (Catalog tham chiếu packages/Shop.Contracts): docker build -t starci-shop/catalog:dev .
FROM mcr.microsoft.com/dotnet/sdk:10.0

WORKDIR /src

# Copy .csproj và restore TRƯỚC khi copy source (tận dụng layer cache).
COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/
COPY services/Catalog/Catalog.csproj services/Catalog/
RUN dotnet restore services/Catalog/Catalog.csproj

# Copy toàn bộ source rồi publish.
COPY packages/Shop.Contracts/ packages/Shop.Contracts/
COPY services/Catalog/ services/Catalog/
RUN dotnet publish services/Catalog/Catalog.csproj -c Release -o /app --no-restore

WORKDIR /app
# PORT và CATALOG_DATABASE_URL đọc từ env lúc chạy (không nướng vào image).
ENTRYPOINT ["dotnet", "Catalog.dll"]
