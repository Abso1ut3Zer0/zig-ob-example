const std = @import("std");
const comm = @import("./common.zig");

pub fn OrderBookSide(comptime side: comm.Side, comptime size: usize) type {
    return struct {
        const Self = @This();
        orders: RingBuffer(size),

        pub fn init() Self {
            return .{ .orders = RingBuffer(size).init() };
        }

        pub fn addOrder(self: *Self, order: comm.Order) void {
            for (0..self.orders.len) |i| {
                if (comptime side == .buy) {
                    if (order.price > self.orders.get(i).price) {
                        self.orders.insert(i, .{
                            .price = order.price,
                            .qty = order.qty,
                        });
                        return;
                    } else if (order.price == self.orders.get(i).price) {
                        self.orders.get(i).qty = order.qty;
                        return;
                    }
                } else {
                    if (order.price < self.orders.get(i).price) {
                        self.orders.insert(i, .{
                            .price = order.price,
                            .qty = order.qty,
                        });
                        return;
                    } else if (order.price == self.orders.get(i).price) {
                        self.orders.get(i).qty = order.qty;
                        return;
                    }
                }
            }

            self.orders.append(.{ .price = order.price, .qty = order.qty });
        }

        fn priceForQty(self: *Self, qty: f64) f64 {
            var num: f64 = 0.0;
            var rem = qty;
            var idx: usize = 0;
            while (rem > 0.0 and idx < self.orders.len) : (idx += 1) {
                const q = @min(rem, self.orders.get(idx).qty);
                num += q * self.orders.get(idx).price;
                rem -= q;
            }

            if (rem > 0.0) {
                return std.math.nan(f64);
            }

            return num / qty;
        }
    };
}

fn RingBuffer(comptime size: usize) type {
    return struct {
        const Self = @This();
        buf: [size]comm.Layer,
        head: usize,
        len: usize,
        cap: usize,

        pub fn init() Self {
            return .{
                .buf = undefined,
                .head = 0,
                .len = 0,
                .cap = size,
            };
        }

        pub inline fn append(self: *Self, layer: comm.Layer) void {
            self.insert(self.len, layer);
        }

        // Note: idx is relative to the head, not the actual index!
        pub fn insert(self: *Self, idx: usize, layer: comm.Layer) void {
            // If we are inserting at the front, we can just overwrite
            // the worst layer and move the head back one!
            if (idx == 0) {
                self.head = (self.head + self.buf.len - 1) % self.buf.len;
                self.buf[(self.head + idx) % self.buf.len] = layer;
                self.len = @min(self.len + 1, self.cap);
                return;
            }

            const back = (self.head + self.buf.len - 1) % self.buf.len;
            const pivot = (self.head + idx) % self.buf.len;

            // If we are inserting at the back, we just overwrite it.
            if (back == pivot) {
                self.buf[back] = layer;
                self.len = @min(self.len + 1, self.cap);
                return;
            }

            if (pivot < self.head) {
                // Shift from the pivot to the head, overwritng
                // the worst entry, then set the pivot to the
                // new layer.
                std.mem.copyForwards(
                    comm.Layer,
                    self.buf[pivot + 1 .. self.head],
                    self.buf[pivot..back],
                );
                self.buf[pivot] = layer;
                self.len = @min(self.len + 1, self.cap);
                return;
            } else {
                // Make room at the front by shifting everything
                // to the left of the head over by one while
                // overwriting the worst entry. But don't forget
                // to make sure there are items before the head!
                if (self.head != 0) {
                    std.mem.copyForwards(
                        comm.Layer,
                        self.buf[1..self.head],
                        self.buf[0..back],
                    );

                    // Wrap the end of the buffer to the front now that
                    // there is room, then shift everything from the pivot
                    // to the end of the buffer.
                    self.buf[0] = self.buf[self.buf.len - 1];
                }
                std.mem.copyForwards(
                    comm.Layer,
                    self.buf[pivot + 1 .. self.buf.len],
                    self.buf[pivot .. self.buf.len - 1],
                );
                self.buf[pivot] = layer;
                self.len = @min(self.len + 1, self.cap);
                return;
            }
        }

        pub inline fn get(self: *Self, idx: usize) *comm.Layer {
            return &self.buf[(self.head + idx) % self.cap];
        }
    };
}

test "obside4 adding bids uniformly" {
    std.debug.print("Start OBSide4 Adding Bids Uniformly\n", .{});
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
    std.debug.print("End OBSide4 Adding Bids Uniformly\n\n", .{});
}

test "obside4 adding bids normally around best price" {
    std.debug.print("Start OBSide4 Adding Bids Normally\n", .{});
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
    std.debug.print("End OBSide4 Adding Bids Normally\n\n", .{});
}

test "test ring buffer" {
    var buf = RingBuffer(3).init();
    buf.insert(0, .{ .price = 1, .qty = 1 });
    for (0..buf.len) |i| {
        std.debug.print("{any}\n", .{buf.buf[i]});
    }
    std.debug.print("Buffer: {any}\n", .{buf.buf});

    buf.insert(0, .{ .price = 2, .qty = 2 });
    for (0..buf.len) |i| {
        std.debug.print("{any}\n", .{buf.buf[i]});
    }
    std.debug.print("Buffer: {any}\n", .{buf.buf});

    buf.insert(1, .{ .price = 3, .qty = 3 });
    for (0..buf.len) |i| {
        std.debug.print("{any}\n", .{buf.buf[i]});
    }
    std.debug.print("Buffer: {any}\n", .{buf.buf});

    buf.insert(2, .{ .price = 4, .qty = 4 });
    for (0..buf.len) |i| {
        std.debug.print("{any}\n", .{buf.buf[i]});
    }
    std.debug.print("Buffer: {any}\n", .{buf.buf});
}
