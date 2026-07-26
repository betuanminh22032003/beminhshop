# Dockerfile ĐA TẦNG cho service Catalog (.NET). Build context = GỐC repo
# (Catalog tham chiếu packages/Shop.Contracts). Đừng `docker build` tay nữa —
# `bash scripts/build-images.sh` tag theo git SHA và truyền ARG GIT_SHA cho cả 4 service.
# Bản đơn tầng cũ giữ ở Dockerfile.single để so kích thước (SDK lên tận production).
#
# TÁI LẬP ĐƯỢC: base ghim bằng DIGEST (không phải tag trôi nổi), NuGet ghim bằng
# packages.lock.json đã commit + restore ở locked mode ⇒ cùng một commit, cùng một image.

# --- tầng build: full .NET SDK, ghim digest ---
FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:3dae2f7699441af56216ff64d5c9b6dfce7cd7dc7f4f71d353d29662b10a384f AS build
WORKDIR /src

# .csproj + packages.lock.json TRƯỚC source: layer restore chỉ mất cache khi dependency
# đổi, nên sửa một file .cs KHÔNG kéo lại gói NuGet nào (lần build sau in ra CACHED).
COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/packages.lock.json packages/Shop.Contracts/
COPY services/Catalog/Catalog.csproj services/Catalog/packages.lock.json services/Catalog/
# --locked-mode: lockfile lệch csproj thì FAIL build, không âm thầm resolve version khác.
RUN dotnet restore services/Catalog/Catalog.csproj --locked-mode

# Source copy SAU restore.
COPY packages/Shop.Contracts/ packages/Shop.Contracts/
COPY services/Catalog/ services/Catalog/
RUN dotnet publish services/Catalog/Catalog.csproj -c Release -o /app/publish --no-restore

# --- tầng runtime: CHỈ ASP.NET runtime (ghim digest), không SDK, không chạy root ---
FROM mcr.microsoft.com/dotnet/aspnet:10.0@sha256:1f51d2d65ace46d6395e773fb4cfc1c74d36fb4f08e5cf996e7f6961b45e9283 AS runtime

# GIT_SHA tiêm lúc build, KHÔNG default về giá trị trôi nổi: build thiếu ARG thì version
# rỗng và thấy ngay, thay vì gắn nhãn sai cho một image.
ARG GIT_SHA
RUN test -n "${GIT_SHA}" || (echo "GIT_SHA build arg is required" >&2; exit 1)
ENV APP_VERSION=${GIT_SHA} \
    DOTNET_RUNNING_IN_CONTAINER=true

# Image tự khai danh tính: `docker inspect` đọc ra đúng commit đã sinh ra nó.
LABEL org.opencontainers.image.revision=${GIT_SHA} \
      org.opencontainers.image.version=${GIT_SHA} \
      org.opencontainers.image.title=starci-shop/catalog \
      org.opencontainers.image.source=https://github.com/betuanminh22032003/beminhshop

WORKDIR /app

# CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
COPY --from=build /app/publish ./

# Image aspnet có sẵn user không phải root tên "app".
USER app
EXPOSE 3001
# PORT và CATALOG_DATABASE_URL đọc từ env lúc chạy (không nướng vào image).
ENTRYPOINT ["dotnet", "Catalog.dll"]
