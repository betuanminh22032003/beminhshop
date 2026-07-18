namespace Shop.Contracts;

// Bọc lại để không thể truyền một string thô vào nơi cần một product id.
public readonly record struct ProductId(string Value);
