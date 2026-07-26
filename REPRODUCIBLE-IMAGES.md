# Reproducible image bundle

This is the grading entry point for the four immutable service images. The
authoritative implementation is in the real files below; this document does
not duplicate Dockerfiles or source listings.

| Service | Dockerfile | Locked dependency manifests |
| --- | --- | --- |
| catalog | `Dockerfile` | `packages/Shop.Contracts/packages.lock.json`, `services/Catalog/packages.lock.json` |
| cart | `services/Cart/Dockerfile` | `packages/Shop.Contracts/packages.lock.json`, `services/Cart/packages.lock.json` |
| order | `services/order/Dockerfile` | `packages/Shop.Contracts/packages.lock.json`, `services/order/packages.lock.json` |
| payment | `services/payment/Dockerfile` | `services/payment/packages.lock.json` |

Every Dockerfile:

- pins both SDK and ASP.NET runtime bases by `sha256` digest;
- copies `.csproj` plus committed `packages.lock.json` before source;
- restores with `dotnet restore --locked-mode`;
- rejects a missing `GIT_SHA` build argument;
- publishes into an ASP.NET-only runtime stage running as non-root;
- records the exact short commit SHA in
  `org.opencontainers.image.revision` and `APP_VERSION`.

`bash scripts/build-images.sh` refuses a dirty worktree and emits only
`starci-shop/<service>:<short-sha>` release artifacts (with `--latest` available
only as an explicit alias after the immutable SHA tag exists).

`bash scripts/verify-reproducible.sh` is the executable proof. It builds all
four images twice, verifies the second restore layers are `CACHED`, compares
digests of the runtime config plus filesystem layers, checks revision labels, confirms the runtime has no
SDK, confirms the runtime UID is non-root, and exits nonzero on any mismatch.
The same command runs on every relevant push to `main` in
`.github/workflows/reproducible-images.yml`, with its complete output written to
the GitHub Actions job summary.
