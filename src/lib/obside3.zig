const std = @import("std");
const comm = @import("./common.zig");

pub fn OrderBookSide(comptime side: comm.Side, comptime size: usize) type {
    return struct {
        const Self = @This();
        orders: std.BoundedArray(comm.Layer, size),

        pub fn init() Self {
            return .{ .orders = std.BoundedArray(
                comm.Layer,
                size,
            ).init(0) catch {
                unreachable;
            } };
        }

        pub fn addOrder(self: *Self, order: comm.Order) void {
            for (0..self.orders.len) |i| {
                if (comptime side == .buy) {
                    if (order.price > self.orders.buffer[i].price) {
                        if (self.orders.capacity() == self.orders.len) {
                            _ = self.orders.pop();
                        }
                        self.orders.insert(i, .{
                            .price = order.price,
                            .qty = order.qty,
                        }) catch unreachable;
                        return;
                    } else if (order.price == self.orders.buffer[i].price) {
                        self.orders.buffer[i].qty = order.qty;
                        return;
                    }
                } else {
                    if (order.price < self.orders.buffer[i].price) {
                        if (self.orders.capacity() == self.orders.len) {
                            _ = self.orders.pop();
                        }
                        self.orders.insert(i, .{
                            .price = order.price,
                            .qty = order.qty,
                        }) catch unreachable;
                        return;
                    } else if (order.price == self.orders.buffer[i].price) {
                        self.orders.buffer[i].qty = order.qty;
                        return;
                    }
                }
            }

            self.orders.append(.{ .price = order.price, .qty = order.qty }) catch unreachable;
        }

        fn priceForQty(self: *Self, qty: f64) f64 {
            var num: f64 = 0.0;
            var rem = qty;
            var idx: usize = 0;
            while (rem > 0.0 and idx < self.orders.len) : (idx += 1) {
                const q = @min(rem, self.orders.buffer[idx].qty);
                num += q * self.orders.buffer[idx].price;
                rem -= q;
            }

            if (rem > 0.0) {
                return std.math.nan(f64);
            }

            return num / qty;
        }
    };
}

test "obside3 adding bids uniformly" {
    std.debug.print("Start OBSide3 Adding Bids Uniformly\n", .{});
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

        var bids = OrderBookSide(.buy, 150).init();
        {
            const start = std.time.nanoTimestamp();
            for (0..count) |_| {
                const int_offset = rng.intRangeAtMost(i64, -range, range);
                const offset: f64 = @floatFromInt(int_offset);
                const scaled = offset * step_size;

                bids.addOrder(.{
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
    std.debug.print("End OBSide3 Adding Bids Uniformly\n\n", .{});
}

test "obside3 adding bids normally around best price" {
    std.debug.print("Start OBSide3 Adding Bids Normally\n", .{});
    const seed = 100;
    const rand = std.rand.DefaultPrng.init(seed);
    const rng = @constCast(&rand).random();

    var best: f64 = 1;
    const step_size: f64 = 0.01;
    const count = 100_000;
    const ordqty = 25.0;
    const minrange = 5;
    const iters = 5;

    for (0..iters) |i| {
        const i_64: i64 = @intCast(i);
        const range = minrange * std.math.pow(i64, 10, i_64);
        std.debug.print("Using Range: {d}\n", .{range});

        var bids = OrderBookSide(.buy, 150).init();
        {
            const start = std.time.nanoTimestamp();
            for (0..count) |_| {
                const rand_offset = rng.floatNorm(f64);
                const unscaled: i64 = @intFromFloat(std.math.round(rand_offset * 100));
                const int_offset: i64 = range * @divTrunc(unscaled, 100);
                const offset: f64 = @floatFromInt(int_offset);
                const scaled = offset * step_size;

                bids.addOrder(.{
                    .symbol = "EURUSD",
                    .price = best + scaled,
                    .qty = ordqty,
                    .side = .buy,
                });

                best = @max(best, best + scaled);
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
    std.debug.print("End OBSide3 Adding Bids Normally\n\n", .{});
}
