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

        pub fn hasOnset(self: Self) bool {
            if (self.whole) |whole| {
                return whole.begin.eql(self.part.begin);
            }
            return false;
        }

        pub fn wholeOrPart(self: Self) TimeSpan {
            return self.whole orelse self.part;
        }

        pub fn duration(self: Self) Fraction {
            if (self.whole) |whole| {
                return whole.duration();
            }
            return self.part.duration();
        }
    };
}

const std = @import("std");

test "has onset" {
    const whole = TimeSpan.fromIntegers(0, 1);
    const part = TimeSpan.init(Fraction.init(0, 1), Fraction.init(1, 2));
    const hap = Hap(i32).init(whole, part, 42);

    try std.testing.expect(hap.hasOnset());

    const part2 = TimeSpan.init(Fraction.init(1, 2), Fraction.init(1, 1));
    const hap2 = Hap(i32).init(whole, part2, 42);
    try std.testing.expect(!hap2.hasOnset());
}

test "duration" {
    const whole = TimeSpan.init(Fraction.init(0, 1), Fraction.init(1, 2));
    const hap = Hap(i32).init(whole, whole, 42);

    try std.testing.expectEqual(Fraction.init(1, 2), hap.duration());
}
