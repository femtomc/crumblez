const std = @import("std");
const Fraction = @import("fraction.zig").Fraction;
const Hap = @import("hap.zig").Hap;
const State = @import("state.zig").State;
const TimeSpan = @import("timespan.zig").TimeSpan;

pub fn Pattern(comptime T: type) type {
    return union(enum) {
        silence,
        pure: T,

        const Self = @This();

        pub fn query(self: Self, allocator: std.mem.Allocator, state: State) ![]Hap(T) {
            switch (self) {
                .silence => {
                    return allocator.alloc(Hap(T), 0);
                },
                .pure => |value| {
                    const cycles = try state.span.spanCycles(allocator);
                    defer allocator.free(cycles);

                    const out = try allocator.alloc(Hap(T), cycles.len);
                    for (cycles, 0..) |subspan, i| {
                        const whole = subspan.begin.wholeCycle();
                        out[i] = Hap(T).init(
                            TimeSpan.init(whole.begin, whole.end),
                            subspan,
                            value,
                        );
                    }
                    return out;
                },
            }
        }

        pub fn queryArc(self: Self, allocator: std.mem.Allocator, begin: Fraction, end: Fraction) ![]Hap(T) {
            const state = State.init(TimeSpan.init(begin, end));
            return self.query(allocator, state);
        }

        pub fn firstCycle(self: Self, allocator: std.mem.Allocator) ![]Hap(T) {
            return self.queryArc(allocator, Fraction.zero(), Fraction.one());
        }

        pub fn fast(self: Self, _: Fraction) Self {
            // TODO(port): implement fast once we add composable pattern transforms.
            return self;
        }

        pub fn slow(self: Self, _: Fraction) Self {
            // TODO(port): implement slow once we add composable pattern transforms.
            return self;
        }
    };
}

pub fn silence(comptime T: type) Pattern(T) {
    return .silence;
}

pub fn pure(value: anytype) Pattern(@TypeOf(value)) {
    return .{ .pure = value };
}

test "pure first cycle" {
    const pat = pure(@as(i32, 42));
    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 1), haps.len);
    try std.testing.expectEqual(@as(i32, 42), haps[0].value);
}

test "silence has no events" {
    const pat = silence(i32);
    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 0), haps.len);
}

test "pure over two cycles returns two events" {
    const pat = pure(@as(u8, 7));
    const haps = try pat.queryArc(
        std.testing.allocator,
        Fraction.fromInteger(0),
        Fraction.fromInteger(2),
    );
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 2), haps.len);
    try std.testing.expectEqual(@as(u8, 7), haps[0].value);
    try std.testing.expectEqual(@as(u8, 7), haps[1].value);
}
