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

# curl là công cụ DUY NHẤT thêm vào runtime, để HEALTHCHECK tự thăm dò /health được.
# Cài trước khi hạ quyền (apt cần root), rồi dọn apt lists cho image gọn.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
COPY --from=build /app/publish ./

# Image aspnet có sẵn user không phải root tên "app".
USER app
EXPOSE 3003
# PORT / CATALOG_URL / CART_URL / DATABASE_URL đọc từ env lúc chạy (không nướng vào image).

# Container tự thăm dò /health — endpoint đó chạy `SELECT 1` thật tới Postgres, nên
# "healthy" ở đây nghĩa là order THỰC SỰ nói chuyện được với DB, không chỉ còn sống.
# Dạng shell (không phải exec) để ${PORT} nở lúc chạy — cổng vẫn do env quyết định.
# curl -f thoát khác 0 khi HTTP >= 400, nên 503 lập tức thành "unhealthy".
HEALTHCHECK --interval=10s --timeout=3s --retries=5 --start-period=20s \
    CMD curl -fsS "http://localhost:${PORT:-3003}/health" || exit 1

ENTRYPOINT ["dotnet", "order.dll"]
