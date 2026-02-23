const std = @import("std");

pub const Fraction = struct {
    numer: i64,
    denom: i64,

    pub const FromF64Error = error{
        NonFinite,
        Overflow,
    };

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

        const g = gcdU64(absToU64(n), absToU64(d));
        return .{
            .numer = @divTrunc(n, @as(i64, @intCast(g))),
            .denom = @divTrunc(d, @as(i64, @intCast(g))),
        };
    }

    pub fn fromInteger(n: i64) Fraction {
        return .{ .numer = n, .denom = 1 };
    }

    pub fn fromF64(value: f64) FromF64Error!Fraction {
        if (!std.math.isFinite(value)) return error.NonFinite;
        if (value == 0.0) return zero();

        const bits: u64 = @bitCast(value);
        const sign_neg = (bits >> 63) != 0;
        const exp_bits = @as(u11, @intCast((bits >> 52) & 0x7ff));
        const frac_bits = bits & 0x000f_ffff_ffff_ffff;

        const mantissa: u64 = if (exp_bits == 0)
            frac_bits
        else
            (1 << 52) | frac_bits;

        if (mantissa == 0) return zero();

        const unbiased_exp: i32 = if (exp_bits == 0)
            -1022
        else
            @as(i32, exp_bits) - 1023;
        const exponent: i32 = unbiased_exp - 52;

        var numer_mag: u64 = 0;
        var denom: i64 = 1;

        if (exponent >= 0) {
            const shift: u6 = @intCast(exponent);
            const top_bit: u7 = @intCast(64 - @clz(mantissa) - 1);
            if (@as(u16, top_bit) + shift > 62) return error.Overflow;
            numer_mag = mantissa << shift;
        } else {
            const denom_shift_i32 = -exponent;
            if (denom_shift_i32 > 1024) return error.Overflow;
            const denom_shift: u16 = @intCast(denom_shift_i32);

            const reducible = @min(denom_shift, @as(u16, @intCast(@ctz(mantissa))));
            numer_mag = mantissa >> @as(u6, @intCast(reducible));
            const reduced_denom_shift = denom_shift - reducible;

            if (reduced_denom_shift > 62) return error.Overflow;
            denom = @as(i64, 1) << @as(u6, @intCast(reduced_denom_shift));
        }

        if (numer_mag > std.math.maxInt(i64)) return error.Overflow;
        const numer: i64 = if (sign_neg)
            -@as(i64, @intCast(numer_mag))
        else
            @as(i64, @intCast(numer_mag));

        return init(numer, denom);
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

pub fn gcdU64(a0: u64, b0: u64) u64 {
    var a = a0;
    var b = b0;

    while (b != 0) {
        const t = @mod(a, b);
        a = b;
        b = t;
    }

    return if (a == 0) 1 else a;
}

pub fn lcmU64(a: u64, b: u64) u64 {
    if (a == 0 or b == 0) return 0;
    return (a / gcdU64(a, b)) * b;
}

pub fn gcdI64(a: i64, b: i64) u64 {
    return gcdU64(absToU64(a), absToU64(b));
}

pub fn lcmI64(a: i64, b: i64) u64 {
    return lcmU64(absToU64(a), absToU64(b));
}

fn absToU64(v: i64) u64 {
    std.debug.assert(v != std.math.minInt(i64));
    return @intCast(@abs(v));
}

test "sam" {
    try std.testing.expectEqual(Fraction.init(0, 1), Fraction.init(0, 1).sam());
    try std.testing.expectEqual(Fraction.init(0, 1), Fraction.init(1, 2).sam());
    try std.testing.expectEqual(Fraction.init(1, 1), Fraction.init(3, 2).sam());
    try std.testing.expectEqual(Fraction.init(2, 1), Fraction.init(5, 2).sam());
    try std.testing.expectEqual(Fraction.init(-1, 1), Fraction.init(-1, 4).sam());
}

test "next sam" {
    try std.testing.expectEqual(Fraction.init(1, 1), Fraction.init(0, 1).nextSam());
    try std.testing.expectEqual(Fraction.init(1, 1), Fraction.init(1, 2).nextSam());
    try std.testing.expectEqual(Fraction.init(2, 1), Fraction.init(3, 2).nextSam());
    try std.testing.expectEqual(Fraction.init(0, 1), Fraction.init(-1, 4).nextSam());
}

test "cycle pos" {
    try std.testing.expectEqual(Fraction.init(0, 1), Fraction.init(0, 1).cyclePos());
    try std.testing.expectEqual(Fraction.init(1, 2), Fraction.init(1, 2).cyclePos());
    try std.testing.expectEqual(Fraction.init(1, 2), Fraction.init(3, 2).cyclePos());
    try std.testing.expectEqual(Fraction.init(3, 4), Fraction.init(7, 4).cyclePos());
    try std.testing.expectEqual(Fraction.init(3, 4), Fraction.init(-1, 4).cyclePos());
}

test "arithmetic" {
    const a = Fraction.init(1, 2);
    const b = Fraction.init(1, 3);

    try std.testing.expectEqual(Fraction.init(5, 6), a.add(b));
    try std.testing.expectEqual(Fraction.init(1, 6), a.sub(b));
    try std.testing.expectEqual(Fraction.init(1, 6), a.mul(b));
    try std.testing.expectEqual(Fraction.init(3, 2), a.div(b));
}

test "reduction invariants and zero handling" {
    try std.testing.expectEqual(Fraction.init(1, 2), Fraction.init(2, 4));
    try std.testing.expectEqual(Fraction.init(-1, 2), Fraction.init(2, -4));
    try std.testing.expectEqual(Fraction.init(0, 1), Fraction.init(0, -99));
}

test "cmp min max with negatives" {
    const a = Fraction.init(-3, 4);
    const b = Fraction.init(-2, 3);

    try std.testing.expectEqual(std.math.Order.lt, a.cmp(b));
    try std.testing.expectEqual(a, a.min(b));
    try std.testing.expectEqual(b, a.max(b));
}

test "gcd/lcm helpers" {
    try std.testing.expectEqual(@as(u64, 6), gcdU64(54, 24));
    try std.testing.expectEqual(@as(u64, 216), lcmU64(54, 24));
    try std.testing.expectEqual(@as(u64, 6), gcdI64(-54, 24));
    try std.testing.expectEqual(@as(u64, 216), lcmI64(-54, 24));
    try std.testing.expectEqual(@as(u64, 0), lcmU64(0, 24));
}

test "fromF64 exact finite values" {
    try std.testing.expectEqual(Fraction.init(1, 2), try Fraction.fromF64(0.5));
    try std.testing.expectEqual(Fraction.init(-5, 4), try Fraction.fromF64(-1.25));
    try std.testing.expectEqual(Fraction.init(3, 1), try Fraction.fromF64(3.0));
}

test "fromF64 rejects non-finite and overflowing representations" {
    try std.testing.expectError(Fraction.FromF64Error.NonFinite, Fraction.fromF64(std.math.inf(f64)));
    try std.testing.expectError(Fraction.FromF64Error.NonFinite, Fraction.fromF64(std.math.nan(f64)));
    try std.testing.expectError(Fraction.FromF64Error.Overflow, Fraction.fromF64(std.math.floatMin(f64)));
}
