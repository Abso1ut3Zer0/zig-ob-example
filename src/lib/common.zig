pub const Side = enum {
    buy,
    sell,
};

pub const Order = struct {
    symbol: []const u8,
    price: f64,
    qty: f64,
    side: Side,
};

pub const Layer = struct {
    price: f64,
    qty: f64,
};
