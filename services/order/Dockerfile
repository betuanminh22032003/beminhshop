# Dockerfile ĐA TẦNG cho service order (.NET). Build context = GỐC repo
# (order tham chiếu packages/Shop.Contracts). Build qua `bash scripts/build-images.sh`
# để tag theo git SHA; docker-compose.yaml khai đúng cặp context: . / dockerfile: services/order/Dockerfile.
#
# TÁI LẬP ĐƯỢC: base ghim bằng DIGEST, NuGet ghim bằng packages.lock.json + locked mode.

# --- tầng build: full .NET SDK, ghim digest ---
FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:3dae2f7699441af56216ff64d5c9b6dfce7cd7dc7f4f71d353d29662b10a384f AS build
WORKDIR /src

# .csproj + packages.lock.json TRƯỚC source: layer restore giữ cache tới khi dependency đổi.
COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/packages.lock.json packages/Shop.Contracts/
COPY services/order/order.csproj services/order/packages.lock.json services/order/
# --locked-mode: lockfile lệch csproj thì FAIL build, không âm thầm resolve version khác.
RUN dotnet restore services/order/order.csproj --locked-mode

# Source copy SAU restore.
COPY packages/Shop.Contracts/ packages/Shop.Contracts/
COPY services/order/ services/order/
RUN dotnet publish services/order/order.csproj -c Release -o /app/publish --no-restore

# --- tầng runtime: CHỈ ASP.NET runtime (ghim digest), không SDK, không chạy root ---
FROM mcr.microsoft.com/dotnet/aspnet:10.0@sha256:1f51d2d65ace46d6395e773fb4cfc1c74d36fb4f08e5cf996e7f6961b45e9283 AS runtime

ARG GIT_SHA
RUN test -n "${GIT_SHA}" || (echo "GIT_SHA build arg is required" >&2; exit 1)
ENV APP_VERSION=${GIT_SHA} \
    DOTNET_RUNNING_IN_CONTAINER=true

LABEL org.opencontainers.image.revision=${GIT_SHA} \
      org.opencontainers.image.version=${GIT_SHA} \
      org.opencontainers.image.title=starci-shop/order \
      org.opencontainers.image.source=https://github.com/betuanminh22032003/beminhshop

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
