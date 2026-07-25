using Npgsql;

namespace Catalog;

/// <summary>Một dòng sản phẩm — shape JSON giữ nguyên { id, title, priceCents }.</summary>
public record Product(string Id, string Title, int PriceCents);

/// <summary>
/// Nguồn sản phẩm của Catalog. Dữ liệu nằm trong Postgres (compose: service "db"),
/// nên nó sống lâu hơn container: bảng nằm trên named volume pgdata, seed CHỈ chạy khi
/// bảng còn rỗng — sau `docker compose down && up` dữ liệu cũ vẫn còn và seed bị bỏ qua.
/// Nếu không có DB (chạy dev bằng scripts/dev.sh, không Docker), store rơi về seed
/// in-memory để service vẫn boot được — trạng thái đó ghi rõ trong log.
/// </summary>
public sealed class ProductStore(string databaseUrl)
{
    // Seed gốc: cũng chính là dữ liệu ghi vào Postgres lần đầu tiên.
    private static readonly Product[] SeedProducts =
    [
        new("sku-001", "Starter Mug", 1200),
        new("sku-002", "Field Notebook", 800),
        new("sku-003", "Enamel Pin", 500),
    ];

    private readonly string _connectionString = ToConnectionString(databaseUrl);

    /// <summary>true = đọc/ghi Postgres thật; false = fallback seed in-memory.</summary>
    public bool UsesDatabase { get; private set; }

    /// <summary>
    /// Tạo bảng nếu chưa có rồi seed KHI VÀ CHỈ KHI bảng rỗng. Retry vì Postgres có thể
    /// chưa nhận kết nối ngay (compose đã có depends_on: service_healthy, nhưng chạy tay thì không).
    /// </summary>
    public async Task<bool> InitializeAsync(int attempts = 5, int delayMs = 1000)
    {
        for (var attempt = 1; attempt <= attempts; attempt++)
        {
            try
            {
                await using var db = new NpgsqlConnection(_connectionString);
                await db.OpenAsync();

                await using (var create = new NpgsqlCommand(
                    """
                    CREATE TABLE IF NOT EXISTS products (
                        id          text    PRIMARY KEY,
                        title       text    NOT NULL,
                        price_cents integer NOT NULL
                    )
                    """, db))
                {
                    await create.ExecuteNonQueryAsync();
                }

                await using (var count = new NpgsqlCommand("SELECT count(*) FROM products", db))
                {
                    var existing = Convert.ToInt64(await count.ExecuteScalarAsync());
                    if (existing > 0)
                    {
                        // Bằng chứng dữ liệu bền bỉ: bảng đã có sẵn từ lần boot trước (volume pgdata).
                        Console.WriteLine($"[catalog] products already in db ({existing} rows) — skipping seed");
                        UsesDatabase = true;
                        return true;
                    }
                }

                foreach (var p in SeedProducts)
                {
                    await using var insert = new NpgsqlCommand(
                        "INSERT INTO products (id, title, price_cents) VALUES ($1, $2, $3)", db);
                    insert.Parameters.AddWithValue(p.Id);
                    insert.Parameters.AddWithValue(p.Title);
                    insert.Parameters.AddWithValue(p.PriceCents);
                    await insert.ExecuteNonQueryAsync();
                }
                Console.WriteLine($"[catalog] seeded {SeedProducts.Length} products into db");
                UsesDatabase = true;
                return true;
            }
            catch (Exception ex) when (attempt < attempts)
            {
                Console.WriteLine($"[catalog] db not ready (attempt {attempt}/{attempts}): {ex.Message}");
                await Task.Delay(delayMs);
            }
            catch (Exception ex)
            {
                // Không có Postgres (vd. bash scripts/dev.sh) — vẫn boot, phục vụ seed in-memory.
                Console.WriteLine($"[catalog] WARN db unreachable ({ex.Message}) — serving in-memory seed");
                UsesDatabase = false;
                return false;
            }
        }
        UsesDatabase = false;
        return false;
    }

    /// <summary>Đọc danh sách sản phẩm — từ Postgres nếu có, ngược lại từ seed in-memory.</summary>
    public async Task<IReadOnlyList<Product>> ListAsync()
    {
        if (!UsesDatabase) return SeedProducts;

        var items = new List<Product>();
        await using var db = new NpgsqlConnection(_connectionString);
        await db.OpenAsync();
        await using var query = new NpgsqlCommand(
            "SELECT id, title, price_cents FROM products ORDER BY id", db);
        await using var reader = await query.ExecuteReaderAsync();
        while (await reader.ReadAsync())
            items.Add(new Product(reader.GetString(0), reader.GetString(1), reader.GetInt32(2)));
        return items;
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
            Timeout = 5,
        };
        if (userInfo.Length > 0 && userInfo[0].Length > 0)
            builder.Username = Uri.UnescapeDataString(userInfo[0]);
        if (userInfo.Length > 1)
            builder.Password = Uri.UnescapeDataString(userInfo[1]);
        return builder.ConnectionString;
    }
}
