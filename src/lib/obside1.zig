const std = @import("std");
const comm = @import("./common.zig");

pub fn OrderBookSide(comptime side: comm.Side) type {
    return struct {
        const Self = @This();
        orders: std.ArrayList(comm.Layer),

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{ .orders = std.ArrayList(comm.Layer).init(alloc) };
        }

        pub fn deinit(self: *Self) void {
            self.orders.deinit();
            self.* = undefined;
        }

        pub fn addOrder(self: *Self, order: comm.Order) !void {
            var pos: usize = 0;
            while (pos < self.orders.items.len) {
                if (comptime side == .buy) {
                    if (order.price >= self.orders.items[pos].price) break;
                } else {
                    if (order.price <= self.orders.items[pos].price) break;
                }
                pos += 1;
            }

            if (pos == self.orders.items.len) {
                try self.orders.append(.{ .price = order.price, .qty = order.qty });
            } else if (self.orders.items[pos].price == order.price) {
                self.orders.items[pos].qty = order.qty;
                return;
            } else {
                try self.orders.insert(pos, .{ .price = order.price, .qty = order.qty });
            }
        }

        fn priceForQty(self: *Self, qty: f64) f64 {
            var num: f64 = 0.0;
            var rem = qty;
            var idx: usize = 0;
            while (rem > 0.0 and idx < self.orders.items.len) : (idx += 1) {
                const q = @min(rem, self.orders.items[idx].qty);
                num += q * self.orders.items[idx].price;
                rem -= q;
            }

            if (rem > 0.0) {
                return std.math.nan(f64);
            }

            return num / qty;
        }
    };
}

test "obside1 adding bids uniformly" {
    std.debug.print("Start OBSide1 Adding Bids Uniformly\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const seed = 100;
    const rand = std.rand.DefaultPrng.init(seed);
    const rng = @constCast(&rand).random();

    const initial_price: f64 = 1;
    const step_size: f64 = 0.01;
    const count = 100_000;
    const ordqty = 25.0;
    const minrange = 5;
    const iters = 5;

    for (0..iters) |i| {
        const i_64: i64 = @intCast(i);
        const range = minrange * std.math.pow(i64, 10, i_64);
        std.debug.print("Using Range: {d}\n", .{range});

        var bids = OrderBookSide(.buy).init(alloc);
        defer bids.deinit();
        {
            const start = std.time.nanoTimestamp();
            for (0..count) |_| {
                const int_offset = rng.intRangeAtMost(i64, -range, range);
                const offset: f64 = @floatFromInt(int_offset);
                const scaled = offset * step_size;

                try bids.addOrder(.{
                    .symbol = "EURUSD",
                    .price = initial_price + scaled,
                    .qty = ordqty,
                    .side = .buy,
                });
            }
            const end = std.time.nanoTimestamp();
            std.debug.print("addOrder({d}): {d} ns/op\n", .{
                range,
                @divTrunc(end - start, @as(i128, count)),
            });
        }

        {
            const reqqty = ordqty * 100;
            var sum: f64 = 0.0;
            const start = std.time.nanoTimestamp();
            for (0..count) |_| {
                const price = bids.priceForQty(reqqty);
                sum += price;
            }
            const end = std.time.nanoTimestamp();
            std.debug.print("priceForQty: {d} ns/op\n", .{@divTrunc(end - start, @as(i128, count))});
            std.debug.print("Sum: {d}\n\n", .{sum});
        }
    }
    std.debug.print("End OBSide1 Adding Bids Uniformly\n\n", .{});
}
