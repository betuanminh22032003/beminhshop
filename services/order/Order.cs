using Shop.Contracts;

public sealed record OrderLine(ProductId ProductId, int Quantity, Money UnitPrice);

public sealed class Order
{
    public OrderStatus Status { get; private set; } = OrderStatus.Pending;
    public List<OrderLine> Lines { get; } = new();

    public Money Total()
    {
        var minor = Lines.Sum(l => l.UnitPrice.AmountMinor * l.Quantity);
        return new Money(minor, Currency.USD);
    }
}
