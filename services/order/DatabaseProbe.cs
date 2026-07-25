using Npgsql;

/// <summary>
/// Cầu nối order → Postgres, CHỈ dùng cho readiness probe: mở kết nối thật và chạy
/// `SELECT 1`. Không truy vấn nghiệp vụ nào ở đây — order chưa sở hữu bảng nào.
///
/// Vì sao order cần thứ này: một `/health` chỉ trả "ok" cứng thì vô dụng — Docker
/// HEALTHCHECK và `depends_on: condition: service_healthy` sẽ báo xanh cả khi DB đã
/// chết. Probe phải đi tới DB và về mới nói được sự thật.
///
/// Không tái dùng ProductStore của Catalog: service không tham chiếu project của
/// service khác (luật ranh giới trong AGENTS.md) — đây là plumbing hạ tầng của order.
/// </summary>
public sealed class DatabaseProbe : IAsyncDisposable
{
    private readonly NpgsqlDataSource _dataSource;

    public DatabaseProbe(string databaseUrl)
    {
        ConnectionString = ToConnectionString(databaseUrl);
        _dataSource = NpgsqlDataSource.Create(ConnectionString);
    }

    /// <summary>Connection string ADO đã chuẩn hoá (KHÔNG log — có password).</summary>
    public string ConnectionString { get; }

    /// <summary>
    /// Round-trip thật tới Postgres. Ném ra ngoài nếu DB không nhận kết nối, để
    /// handler /health đổi thành 503 thay vì che lỗi.
    /// </summary>
    public async Task PingAsync(CancellationToken cancellationToken = default)
    {
        await using var cmd = _dataSource.CreateCommand("SELECT 1");
        await cmd.ExecuteScalarAsync(cancellationToken);
    }

    /// <summary>
    /// Đổi URL kiểu `postgres://user:pass@db:5432/shop` (thứ compose tiêm vào) thành
    /// connection string ADO của Npgsql. Host là TÊN SERVICE trong compose ("db"), không localhost.
    /// </summary>
    public static string ToConnectionString(string databaseUrl)
    {
        if (!databaseUrl.Contains("://")) return databaseUrl; // đã là connection string sẵn

        var uri = new Uri(databaseUrl);
        var userInfo = uri.UserInfo.Split(':', 2);
        var builder = new NpgsqlConnectionStringBuilder
        {
            Host = uri.Host,
            Port = uri.IsDefaultPort ? 5432 : uri.Port,
            Database = uri.AbsolutePath.Trim('/'),
            // Probe phải thất bại NHANH: HEALTHCHECK của Docker chỉ cho 3s.
            Timeout = 2,
            CommandTimeout = 2,
        };
        if (userInfo.Length > 0 && userInfo[0].Length > 0)
            builder.Username = Uri.UnescapeDataString(userInfo[0]);
        if (userInfo.Length > 1)
            builder.Password = Uri.UnescapeDataString(userInfo[1]);
        return builder.ConnectionString;
    }

    public ValueTask DisposeAsync() => _dataSource.DisposeAsync();
}
