using Shop.Contracts;

namespace Catalog;

public sealed record PriceQuote(ProductId ProductId, Money Price)
{
    // Catalog đọc trực tiếp AmountMinor từ Money của Shop.Contracts — đổi tên trường
    // trong contracts sẽ phá build ngay tại đây (bằng chứng single source of truth).
    public long PriceMinor => Price.AmountMinor;
}
