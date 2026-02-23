const std = @import("std");

pub const Fraction = struct {
    numer: i64,
    denom: i64,

    pub fn init(numer: i64, denom: i64) Fraction {
        std.debug.assert(denom != 0);

        if (numer == 0) {
            return .{ .numer = 0, .denom = 1 };
        }

        var n = numer;
        var d = denom;

        if (d < 0) {
            n = -n;
            d = -d;
        }

        const g = gcd(absToU64(n), absToU64(d));
        return .{
            .numer = @divTrunc(n, @as(i64, @intCast(g))),
            .denom = @divTrunc(d, @as(i64, @intCast(g))),
        };
    }

    pub fn fromInteger(n: i64) Fraction {
        return .{ .numer = n, .denom = 1 };
    }

    pub fn zero() Fraction {
        return fromInteger(0);
    }

    pub fn one() Fraction {
        return fromInteger(1);
    }

    pub fn isZero(self: Fraction) bool {
        return self.numer == 0;
    }

    pub fn add(self: Fraction, other: Fraction) Fraction {
        return init(
            self.numer * other.denom + other.numer * self.denom,
            self.denom * other.denom,
        );
    }

    pub fn sub(self: Fraction, other: Fraction) Fraction {
        return init(
            self.numer * other.denom - other.numer * self.denom,
            self.denom * other.denom,
        );
    }

    pub fn mul(self: Fraction, other: Fraction) Fraction {
        return init(self.numer * other.numer, self.denom * other.denom);
    }

    pub fn div(self: Fraction, other: Fraction) Fraction {
        std.debug.assert(other.numer != 0);
        return init(self.numer * other.denom, self.denom * other.numer);
    }

    pub fn neg(self: Fraction) Fraction {
        return init(-self.numer, self.denom);
    }

    pub fn abs(self: Fraction) Fraction {
        return if (self.numer < 0) init(-self.numer, self.denom) else self;
    }

    pub fn eql(self: Fraction, other: Fraction) bool {
        return self.numer == other.numer and self.denom == other.denom;
    }

    pub fn cmp(self: Fraction, other: Fraction) std.math.Order {
        const lhs: i128 = @as(i128, self.numer) * @as(i128, other.denom);
        const rhs: i128 = @as(i128, other.numer) * @as(i128, self.denom);
        return std.math.order(lhs, rhs);
    }

    pub fn min(self: Fraction, other: Fraction) Fraction {
        return if (self.cmp(other) == .lt) self else other;
    }

    pub fn max(self: Fraction, other: Fraction) Fraction {
        return if (self.cmp(other) == .gt) self else other;
    }

    pub fn floor(self: Fraction) Fraction {
        return fromInteger(@divFloor(self.numer, self.denom));
    }

    pub fn ceil(self: Fraction) Fraction {
        return fromInteger(-@divFloor(-self.numer, self.denom));
    }

    pub fn sam(self: Fraction) Fraction {
        return self.floor();
    }

    pub fn nextSam(self: Fraction) Fraction {
        return self.sam().add(one());
    }

    pub fn cyclePos(self: Fraction) Fraction {
        return self.sub(self.sam());
    }

    pub const WholeCycle = struct {
        begin: Fraction,
        end: Fraction,
    };

    pub fn wholeCycle(self: Fraction) WholeCycle {
        const begin = self.sam();
        return .{ .begin = begin, .end = begin.add(one()) };
    }

    pub fn toF64(self: Fraction) f64 {
        return @as(f64, @floatFromInt(self.numer)) /
            @as(f64, @floatFromInt(self.denom));
    }

    pub fn format(
        self: Fraction,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{d}/{d}", .{ self.numer, self.denom });
    }
};

fn absToU64(v: i64) u64 {
    return @intCast(@abs(v));
}

fn gcd(a0: u64, b0: u64) u64 {
    var a = a0;
    var b = b0;

    while (b != 0) {
        const t = @mod(a, b);
        a = b;
        b = t;
    }

    return if (a == 0) 1 else a;
}

test "sam" {
    try std.testing.expectEqual(Fraction.init(0, 1), Fraction.init(0, 1).sam());
    try std.testing.expectEqual(Fraction.init(0, 1), Fraction.init(1, 2).sam());
    try std.testing.expectEqual(Fraction.init(1, 1), Fraction.init(3, 2).sam());
    try std.testing.expectEqual(Fraction.init(2, 1), Fraction.init(5, 2).sam());
}

test "next sam" {
    try std.testing.expectEqual(Fraction.init(1, 1), Fraction.init(0, 1).nextSam());
    try std.testing.expectEqual(Fraction.init(1, 1), Fraction.init(1, 2).nextSam());
    try std.testing.expectEqual(Fraction.init(2, 1), Fraction.init(3, 2).nextSam());
}

test "cycle pos" {
    try std.testing.expectEqual(Fraction.init(0, 1), Fraction.init(0, 1).cyclePos());
    try std.testing.expectEqual(Fraction.init(1, 2), Fraction.init(1, 2).cyclePos());
    try std.testing.expectEqual(Fraction.init(1, 2), Fraction.init(3, 2).cyclePos());
    try std.testing.expectEqual(Fraction.init(3, 4), Fraction.init(7, 4).cyclePos());
}

test "arithmetic" {
    const a = Fraction.init(1, 2);
    const b = Fraction.init(1, 3);

    try std.testing.expectEqual(Fraction.init(5, 6), a.add(b));
    try std.testing.expectEqual(Fraction.init(1, 6), a.sub(b));
    try std.testing.expectEqual(Fraction.init(1, 6), a.mul(b));
    try std.testing.expectEqual(Fraction.init(3, 2), a.div(b));
}
