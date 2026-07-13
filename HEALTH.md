# Health endpoint contract

Each service owns its own `HealthResponse` record and maps an independent,
side-effect-free liveness endpoint. The handlers below are the source of
truth (not a shared project):

| Service | Identity source | Handler |
| --- | --- | --- |
| Catalog | `Config.Load(5001, "catalog").ServiceName` (`SERVICE_NAME` override) | `services/Catalog/Program.cs`: `Results.Ok(HealthResponse.Ok(config.ServiceName))` + `.AllowAnonymous()` |
| Cart | `Config.Load(5002, "cart").ServiceName` (`SERVICE_NAME` override) | `services/Cart/Program.cs`: `Results.Ok(HealthResponse.Ok(config.ServiceName))` + `.AllowAnonymous()` |
| order | `Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "order"` | `services/order/Program.cs`: `Results.Ok(HealthResponse.Ok(serviceName))` + `.AllowAnonymous()` |
| payment | `Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "payment"` | `services/payment/Program.cs`: `Results.Ok(HealthResponse.Ok(serviceName))` + `.AllowAnonymous()` |

Every local `HealthResponse.Ok(...)` constructs `{ Service, Status }` with the
literal status `"ok"`. Therefore `GET /health` returns HTTP 200 JSON of the
form `{"service":"<configured-name>","status":"ok"}`. `.AllowAnonymous()`
makes the endpoint independent of any authentication/authorization middleware
added in a later milestone; the handler performs no database or HTTP calls.

Runtime verification from the repository root:

```powershell
dotnet build
dotnet sln list
```

Run each service on its configured port and request `/health`; stopping one
process only makes that process's port refuse connections—the other processes
remain independently live.
