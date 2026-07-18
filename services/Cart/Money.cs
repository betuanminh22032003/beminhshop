namespace Cart;

public enum Currency { USD, EUR, VND }

// AmountMinor là đơn vị nhỏ nhất dạng số nguyên (cents); không bao giờ là phần lẻ của cent.
public readonly record struct Money(long AmountMinor, Currency Currency);
