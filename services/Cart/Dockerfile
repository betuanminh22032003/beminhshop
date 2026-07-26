# Dockerfile ĐA TẦNG cho service Cart (.NET). Build context = GỐC repo
# (Cart tham chiếu packages/Shop.Contracts). Build qua `bash scripts/build-images.sh`
# để tag theo git SHA; docker-compose.yaml khai đúng cặp context: . / dockerfile: services/Cart/Dockerfile.
#
# TÁI LẬP ĐƯỢC: base ghim bằng DIGEST, NuGet ghim bằng packages.lock.json + locked mode.

# --- tầng build: full .NET SDK, ghim digest ---
FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:3dae2f7699441af56216ff64d5c9b6dfce7cd7dc7f4f71d353d29662b10a384f AS build
WORKDIR /src

# .csproj + packages.lock.json TRƯỚC source: layer restore giữ cache tới khi dependency đổi.
COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/packages.lock.json packages/Shop.Contracts/
COPY services/Cart/Cart.csproj services/Cart/packages.lock.json services/Cart/
# --locked-mode: lockfile lệch csproj thì FAIL build, không âm thầm resolve version khác.
RUN dotnet restore services/Cart/Cart.csproj --locked-mode

# Source copy SAU restore.
COPY packages/Shop.Contracts/ packages/Shop.Contracts/
COPY services/Cart/ services/Cart/
RUN dotnet publish services/Cart/Cart.csproj -c Release -o /app/publish --no-restore

# --- tầng runtime: CHỈ ASP.NET runtime (ghim digest), không SDK, không chạy root ---
FROM mcr.microsoft.com/dotnet/aspnet:10.0@sha256:1f51d2d65ace46d6395e773fb4cfc1c74d36fb4f08e5cf996e7f6961b45e9283 AS runtime

ARG GIT_SHA
RUN test -n "${GIT_SHA}" || (echo "GIT_SHA build arg is required" >&2; exit 1)
ENV APP_VERSION=${GIT_SHA} \
    DOTNET_RUNNING_IN_CONTAINER=true

LABEL org.opencontainers.image.revision=${GIT_SHA} \
      org.opencontainers.image.version=${GIT_SHA} \
      org.opencontainers.image.title=starci-shop/cart \
      org.opencontainers.image.source=https://github.com/betuanminh22032003/beminhshop

WORKDIR /app

# CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
COPY --from=build /app/publish ./

# Image aspnet có sẵn user không phải root tên "app".
USER app
EXPOSE 3002
# PORT / CATALOG_URL / DATABASE_URL đọc từ env lúc chạy (không nướng vào image).
ENTRYPOINT ["dotnet", "Cart.dll"]
