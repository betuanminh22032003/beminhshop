# Dockerfile ĐA TẦNG cho service order (.NET). Build context = GỐC repo
# (order tham chiếu packages/Shop.Contracts):
#   docker build -f services/order/Dockerfile -t starci-shop/order:slim .
# docker-compose.yaml khai đúng cặp context: . / dockerfile: services/order/Dockerfile.

# --- tầng build: full .NET SDK, restore + publish ---
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy .csproj và restore TRƯỚC khi copy source (tận dụng layer cache).
COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/
COPY services/order/order.csproj services/order/
RUN dotnet restore services/order/order.csproj

# Copy source rồi publish ra /app/publish.
COPY packages/Shop.Contracts/ packages/Shop.Contracts/
COPY services/order/ services/order/
RUN dotnet publish services/order/order.csproj -c Release -o /app/publish --no-restore

# --- tầng runtime: CHỈ ASP.NET runtime, không SDK, không chạy root ---
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
ENV DOTNET_RUNNING_IN_CONTAINER=true
WORKDIR /app

# CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
COPY --from=build /app/publish ./

# Image aspnet có sẵn user không phải root tên "app".
USER app
EXPOSE 3003
# PORT / CATALOG_URL / CART_URL / DATABASE_URL đọc từ env lúc chạy (không nướng vào image).
ENTRYPOINT ["dotnet", "order.dll"]
