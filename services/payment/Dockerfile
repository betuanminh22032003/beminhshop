# Dockerfile ĐA TẦNG cho service payment (.NET). Build context = GỐC repo cho ĐỒNG NHẤT
# với ba service kia (payment chưa tham chiếu Shop.Contracts, nhưng giữ cùng một hợp đồng
# context để scripts/build-images.sh gọi cả 4 service bằng cùng một dòng lệnh).
# Build qua `bash scripts/build-images.sh`.
#
# TÁI LẬP ĐƯỢC: base ghim bằng DIGEST, NuGet ghim bằng packages.lock.json + locked mode.

# --- tầng build: full .NET SDK, ghim digest ---
FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:3dae2f7699441af56216ff64d5c9b6dfce7cd7dc7f4f71d353d29662b10a384f AS build
WORKDIR /src

# .csproj + packages.lock.json TRƯỚC source: layer restore giữ cache tới khi dependency đổi.
COPY services/payment/payment.csproj services/payment/packages.lock.json services/payment/
# --locked-mode: lockfile lệch csproj thì FAIL build, không âm thầm resolve version khác.
RUN dotnet restore services/payment/payment.csproj --locked-mode

# Source copy SAU restore.
COPY services/payment/ services/payment/
RUN dotnet publish services/payment/payment.csproj -c Release -o /app/publish --no-restore

# --- tầng runtime: CHỈ ASP.NET runtime (ghim digest), không SDK, không chạy root ---
FROM mcr.microsoft.com/dotnet/aspnet:10.0@sha256:1f51d2d65ace46d6395e773fb4cfc1c74d36fb4f08e5cf996e7f6961b45e9283 AS runtime

ARG GIT_SHA
ENV APP_VERSION=${GIT_SHA} \
    DOTNET_RUNNING_IN_CONTAINER=true

LABEL org.opencontainers.image.revision=${GIT_SHA} \
      org.opencontainers.image.version=${GIT_SHA} \
      org.opencontainers.image.title=starci-shop/payment \
      org.opencontainers.image.source=https://github.com/betuanminh22032003/beminhshop

WORKDIR /app

# CHỈ mang sang output đã publish — toolchain build ở lại tầng builder.
COPY --from=build /app/publish ./

# Image aspnet có sẵn user không phải root tên "app".
USER app
EXPOSE 5004
# PORT / SERVICE_NAME đọc từ env lúc chạy; launchSettings.json chỉ dùng cho dev, KHÔNG vào image.
ENTRYPOINT ["dotnet", "payment.dll"]
