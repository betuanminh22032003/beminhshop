using Shop.Contracts;

namespace Cart;

// Một dòng trong giỏ: item khách đang chọn, chưa đặt đơn.
public sealed record CartLine(ProductId ProductId, int Qty, Money UnitPrice);
