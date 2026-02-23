const std = @import("std");
const Fraction = @import("fraction.zig").Fraction;
const TimeSpan = @import("timespan.zig").TimeSpan;

pub const Location = struct {
    start: usize,
    end: usize,
};

pub const Context = struct {
    locations: []const Location = &.{},
    tags: []const []const u8 = &.{},
};

pub fn Hap(comptime T: type) type {
    return struct {
        whole: ?TimeSpan,
        part: TimeSpan,
        value: T,
        context: Context = .{},

        const Self = @This();

        pub fn init(whole: ?TimeSpan, part: TimeSpan, value: T) Self {
            return .{
                .whole = whole,
                .part = part,
                .value = value,
            };
        }

        pub fn withContext(whole: ?TimeSpan, part: TimeSpan, value: T, context: Context) Self {
            return .{
                .whole = whole,
                .part = part,
                .value = value,
                .context = context,
            };
        }

        pub fn hasOnset(self: Self) bool {
            if (self.whole) |whole| {
                return whole.begin.eql(self.part.begin);
            }
            return false;
        }

        pub fn wholeOrPart(self: Self) TimeSpan {
            return self.whole orelse self.part;
        }

        pub fn withSpan(self: Self, f: *const fn (TimeSpan) TimeSpan) Self {
            return .{
                .whole = if (self.whole) |whole| f(whole) else null,
                .part = f(self.part),
                .value = self.value,
                .context = self.context,
            };
        }

        pub fn withValue(self: Self, comptime U: type, f: *const fn (T) U) Hap(U) {
            return Hap(U){
                .whole = self.whole,
                .part = self.part,
                .value = f(self.value),
                .context = self.context,
            };
        }

        pub fn duration(self: Self) Fraction {
            if (self.whole) |whole| {
                return whole.duration();
            }
            return self.part.duration();
        }

        pub fn spanEquals(self: Self, other: Self) bool {
            return switch (self.whole) {
                null => other.whole == null,
                else => |whole| if (other.whole) |other_whole| whole.eql(other_whole) else false,
            };
        }

        pub fn eql(self: Self, other: Self) bool {
            return self.spanEquals(other) and self.part.eql(other.part) and std.meta.eql(self.value, other.value);
        }
    };
}

fn doubleI32(v: i32) i32 {
    return v * 2;
}

fn widenSpan(span: TimeSpan) TimeSpan {
    return span.withEnd(addHalf);
}

fn addHalf(v: Fraction) Fraction {
    return v.add(Fraction.init(1, 2));
}

test "has onset" {
    const whole = TimeSpan.fromIntegers(0, 1);
    const part = TimeSpan.init(Fraction.init(0, 1), Fraction.init(1, 2));
    const hap = Hap(i32).init(whole, part, 42);

    try std.testing.expect(hap.hasOnset());

    const part2 = TimeSpan.init(Fraction.init(1, 2), Fraction.init(1, 1));
    const hap2 = Hap(i32).init(whole, part2, 42);
    try std.testing.expect(!hap2.hasOnset());
}

test "whole or part" {
    const part = TimeSpan.init(Fraction.init(1, 4), Fraction.init(3, 4));
    const hap_without_whole = Hap(i32).init(null, part, 1);
    try std.testing.expectEqual(part, hap_without_whole.wholeOrPart());

    const whole = TimeSpan.fromIntegers(0, 1);
    const hap_with_whole = Hap(i32).init(whole, part, 1);
    try std.testing.expectEqual(whole, hap_with_whole.wholeOrPart());
}

test "with value" {
    const whole = TimeSpan.fromIntegers(0, 1);
    const hap = Hap(i32).init(whole, whole, 21);
    const mapped = hap.withValue(i32, doubleI32);
    try std.testing.expectEqual(@as(i32, 42), mapped.value);
}

test "with span" {
    const whole = TimeSpan.fromIntegers(0, 1);
    const part = TimeSpan.init(Fraction.init(0, 1), Fraction.init(1, 2));
    const hap = Hap(i32).init(whole, part, 7);
    const widened = hap.withSpan(widenSpan);

    try std.testing.expectEqual(TimeSpan.init(Fraction.init(0, 1), Fraction.init(3, 2)), widened.whole.?);
    try std.testing.expectEqual(TimeSpan.init(Fraction.init(0, 1), Fraction.init(1, 1)), widened.part);
}

test "duration" {
    const whole = TimeSpan.init(Fraction.init(0, 1), Fraction.init(1, 2));
    const hap = Hap(i32).init(whole, whole, 42);

    try std.testing.expectEqual(Fraction.init(1, 2), hap.duration());

    const part_only = Hap(i32).init(null, TimeSpan.init(Fraction.init(3, 4), Fraction.init(1, 1)), 42);
    try std.testing.expectEqual(Fraction.init(1, 4), part_only.duration());
}
