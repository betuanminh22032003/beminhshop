# Health endpoint contract

Each service owns its own `HealthResponse` record and maps an independent,
side-effect-free liveness endpoint. The handlers below are the source of
truth (not a shared project):

| Service | Identity source | Handler |
| --- | --- | --- |
| Catalog | `Config.Load(5001, "catalog").ServiceName` (`SERVICE_NAME` override) | `services/Catalog/Program.cs`: `Results.Ok(HealthResponse.Ok(config.ServiceName))` + `.AllowAnonymous()` |
| Cart | `Config.Load(5002, "cart").ServiceName` (`SERVICE_NAME` override) | `services/Cart/Program.cs`: `Results.Json(new { service = config.ServiceName, status = "ok" })` |
| order | `Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "order"` | `services/order/Program.cs`: `Results.Json(new { service = serviceName, status = "ok" })` |
| payment | `Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "payment"` | `services/payment/Program.cs`: `Results.Ok(HealthResponse.Ok(serviceName))` + `.AllowAnonymous()` |

Catalog and payment build the payload from their own `HealthResponse.Ok(...)`
record (`{ Service, Status }`, literal status `"ok"`) and mark the endpoint
`.AllowAnonymous()`; Cart and order emit the same JSON inline. Either way
`GET /health` returns HTTP 200 JSON of the form
`{"service":"<configured-name>","status":"ok"}`, and no handler performs a
database or HTTP call — including Catalog, whose Postgres access lives only in
`GET /products` (`services/Catalog/ProductStore.cs`), never in `/health`.

Runtime verification from the repository root:

```powershell
dotnet build
dotnet sln list
```

Run each service on its configured port and request `/health`; stopping one
process only makes that process's port refuse connections—the other processes
remain independently live.
