# Dockerfile ĐA TẦNG cho service Cart (.NET). Build context = GỐC repo
# (Cart tham chiếu packages/Shop.Contracts):
#   docker build -f services/Cart/Dockerfile -t starci-shop/cart:slim .
# docker-compose.yaml khai đúng cặp context: . / dockerfile: services/Cart/Dockerfile.

# --- tầng build: full .NET SDK, restore + publish ---
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy .csproj và restore TRƯỚC khi copy source (tận dụng layer cache).
COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/
COPY services/Cart/Cart.csproj services/Cart/
RUN dotnet restore services/Cart/Cart.csproj

# Copy source rồi publish ra /app/publish.
COPY packages/Shop.Contracts/ packages/Shop.Contracts/
COPY services/Cart/ services/Cart/
RUN dotnet publish services/Cart/Cart.csproj -c Release -o /app/publish --no-restore

# --- tầng runtime: CHỈ ASP.NET runtime, không SDK, không chạy root ---
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
ENV DOTNET_RUNNING_IN_CONTAINER=true
WORKDIR /app

# CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
COPY --from=build /app/publish ./

# Image aspnet có sẵn user không phải root tên "app".
USER app
EXPOSE 3002
# PORT / CATALOG_URL / DATABASE_URL đọc từ env lúc chạy (không nướng vào image).
ENTRYPOINT ["dotnet", "Cart.dll"]
