FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:3dae2f7699441af56216ff64d5c9b6dfce7cd7dc7f4f71d353d29662b10a384f AS build
WORKDIR /src

COPY packages/Shop.Contracts/Shop.Contracts.csproj packages/Shop.Contracts/packages.lock.json packages/Shop.Contracts/
COPY services/order/order.csproj services/order/packages.lock.json services/order/
RUN dotnet restore services/order/order.csproj --locked-mode

COPY packages/Shop.Contracts/ packages/Shop.Contracts/
COPY services/order/ services/order/
RUN dotnet publish services/order/order.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0@sha256:1f51d2d65ace46d6395e773fb4cfc1c74d36fb4f08e5cf996e7f6961b45e9283 AS runtime
ARG GIT_SHA
RUN test -n "${GIT_SHA}" || (echo "GIT_SHA build arg is required" >&2; exit 1)
ENV APP_VERSION=${GIT_SHA} DOTNET_RUNNING_IN_CONTAINER=true
LABEL org.opencontainers.image.revision=${GIT_SHA} \
      org.opencontainers.image.version=${GIT_SHA} \
      org.opencontainers.image.title=starci-shop/order \
      org.opencontainers.image.source=https://github.com/betuanminh22032003/beminhshop
WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/publish ./
USER $APP_UID
EXPOSE 3003
HEALTHCHECK --interval=10s --timeout=3s --retries=5 --start-period=20s \
    CMD curl -fsS "http://localhost:${PORT:-3003}/health" || exit 1
ENTRYPOINT ["dotnet", "order.dll"]
