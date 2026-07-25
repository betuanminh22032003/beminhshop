# Dockerfile ĐA TẦNG cho service Catalog (.NET). Build context = GỐC repo
# (Catalog tham chiếu packages/Shop.Contracts): docker build -t starci-shop/catalog:slim .
# Bản đơn tầng cũ giữ ở Dockerfile.single để so kích thước (SDK lên tận production).

# --- tầng build: full .NET SDK, restore + publish ---
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy .csproj và restore TRƯỚC khi copy source (tận dụng layer cache).
COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/
COPY services/Catalog/Catalog.csproj services/Catalog/
RUN dotnet restore services/Catalog/Catalog.csproj

# Copy source rồi publish ra /app/publish.
COPY packages/Shop.Contracts/ packages/Shop.Contracts/
COPY services/Catalog/ services/Catalog/
RUN dotnet publish services/Catalog/Catalog.csproj -c Release -o /app/publish --no-restore

# --- tầng runtime: CHỈ ASP.NET runtime, không SDK, không chạy root ---
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
ENV DOTNET_RUNNING_IN_CONTAINER=true
WORKDIR /app

# CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
COPY --from=build /app/publish ./

# Image aspnet có sẵn user không phải root tên "app".
USER app
EXPOSE 3001
# PORT và CATALOG_DATABASE_URL đọc từ env lúc chạy (không nướng vào image).
ENTRYPOINT ["dotnet", "Catalog.dll"]
