// scripts/health.csx — chạy bằng: dotnet script scripts/health.csx
// Probe /health của từng service trên cổng riêng, in OK/ERR mỗi service,
// thoát mã khác 0 nếu bất kỳ service nào down.
using System.Net.Http;

// 127.0.0.1 chứ KHÔNG "localhost": cả ba service bind 0.0.0.0 (IPv4, để container reachable qua -p),
// còn "localhost" trên Windows phân giải ::1 trước -> HttpClient treo tới timeout dù service vẫn sống.
var targets = new (string Name, string Url)[]
{
    ("catalog", "http://127.0.0.1:5001/health"),
    ("cart", "http://127.0.0.1:5002/health"),
    ("order", "http://127.0.0.1:5003/health"),
};

// NB: 'using var' ở top-level bị dotnet-script parse nhầm thành using-directive → dùng var thường.
var client = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
var allGreen = true;

foreach (var t in targets)
{
    bool ok;
    string detail;
    try
    {
        var res = await client.GetAsync(t.Url);
        ok = res.IsSuccessStatusCode;
        detail = ((int)res.StatusCode).ToString();
    }
    catch (Exception e)
    {
        ok = false;
        detail = e.Message;
    }
    allGreen &= ok;
    Console.WriteLine($"{(ok ? "OK " : "ERR")} {t.Name,-8} {detail}");
}

Console.WriteLine(allGreen ? "ALL GREEN" : "SOME RED");
Environment.Exit(allGreen ? 0 : 1);
