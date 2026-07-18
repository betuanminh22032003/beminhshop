// scripts/health.csx — chạy bằng: dotnet script scripts/health.csx
// Probe /health của từng service trên cổng riêng, in OK/ERR mỗi service,
// thoát mã khác 0 nếu bất kỳ service nào down.
using System.Net.Http;

var targets = new (string Name, string Url)[]
{
    ("catalog", "http://localhost:5001/health"),
    ("cart", "http://localhost:5002/health"),
    ("order", "http://localhost:5003/health"),
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
