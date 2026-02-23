const std = @import("std");
const Fraction = @import("fraction.zig").Fraction;

pub const TimeSpan = struct {
    begin: Fraction,
    end: Fraction,

    pub fn init(begin: Fraction, end: Fraction) TimeSpan {
        return .{ .begin = begin, .end = end };
    }

    pub fn fromIntegers(begin: i64, end: i64) TimeSpan {
        return .{
            .begin = Fraction.fromInteger(begin),
            .end = Fraction.fromInteger(end),
        };
    }

    pub fn duration(self: TimeSpan) Fraction {
        return self.end.sub(self.begin);
    }

    pub fn midpoint(self: TimeSpan) Fraction {
        return self.begin.add(self.duration().div(Fraction.init(2, 1)));
    }

    pub fn spanCycles(self: TimeSpan, allocator: std.mem.Allocator) ![]TimeSpan {
        if (self.begin.eql(self.end)) {
            const out = try allocator.alloc(TimeSpan, 1);
            out[0] = self;
            return out;
        }

        var spans: std.ArrayListUnmanaged(TimeSpan) = .empty;
        errdefer spans.deinit(allocator);

        var begin = self.begin;
        const end = self.end;
        const end_sam = end.sam();

        while (end.cmp(begin) == .gt) {
            if (begin.sam().eql(end_sam)) {
                try spans.append(allocator, .{ .begin = begin, .end = self.end });
                break;
            }

            const next_begin = begin.nextSam();
            try spans.append(allocator, .{ .begin = begin, .end = next_begin });
            begin = next_begin;
        }

        return spans.toOwnedSlice(allocator);
    }

    pub fn cycleArc(self: TimeSpan) TimeSpan {
        const b = self.begin.cyclePos();
        return .{ .begin = b, .end = b.add(self.duration()) };
    }

    pub fn withTime(self: TimeSpan, f: *const fn (Fraction) Fraction) TimeSpan {
        return .{ .begin = f(self.begin), .end = f(self.end) };
    }

    pub fn withEnd(self: TimeSpan, f: *const fn (Fraction) Fraction) TimeSpan {
        return .{ .begin = self.begin, .end = f(self.end) };
    }

    pub fn withCycle(self: TimeSpan, f: *const fn (Fraction) Fraction) TimeSpan {
        const sam = self.begin.sam();
        const b = sam.add(f(self.begin.sub(sam)));
        const e = sam.add(f(self.end.sub(sam)));
        return .{ .begin = b, .end = e };
    }

    pub fn intersection(self: TimeSpan, other: TimeSpan) ?TimeSpan {
        const intersect_begin = self.begin.max(other.begin);
        const intersect_end = self.end.min(other.end);

        if (intersect_begin.cmp(intersect_end) == .gt) {
            return null;
        }

        if (intersect_begin.eql(intersect_end)) {
            if (intersect_begin.eql(self.end) and self.begin.cmp(self.end) == .lt) {
                return null;
            }
            if (intersect_begin.eql(other.end) and other.begin.cmp(other.end) == .lt) {
                return null;
            }
        }

        return .{ .begin = intersect_begin, .end = intersect_end };
    }

    pub fn intersectionE(self: TimeSpan, other: TimeSpan) TimeSpan {
        return self.intersection(other) orelse @panic("TimeSpans do not intersect");
    }

    pub fn eql(self: TimeSpan, other: TimeSpan) bool {
        return self.begin.eql(other.begin) and self.end.eql(other.end);
    }

    pub fn format(
        self: TimeSpan,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{} -> {}", .{ self.begin, self.end });
    }
};

fn addOne(v: Fraction) Fraction {
    return v.add(Fraction.one());
}

fn halfCycle(v: Fraction) Fraction {
    return v.div(Fraction.init(2, 1));
}

test "span cycles single" {
    const span = TimeSpan.init(Fraction.init(0, 1), Fraction.init(1, 1));
    const cycles = try span.spanCycles(std.testing.allocator);
    defer std.testing.allocator.free(cycles);

    try std.testing.expectEqual(@as(usize, 1), cycles.len);
    try std.testing.expectEqual(span, cycles[0]);
}

test "span cycles zero-width" {
    const span = TimeSpan.init(Fraction.init(3, 2), Fraction.init(3, 2));
    const cycles = try span.spanCycles(std.testing.allocator);
    defer std.testing.allocator.free(cycles);

    try std.testing.expectEqual(@as(usize, 1), cycles.len);
    try std.testing.expectEqual(span, cycles[0]);
}

test "span cycles multiple" {
    const span = TimeSpan.init(Fraction.init(0, 1), Fraction.init(2, 1));
    const cycles = try span.spanCycles(std.testing.allocator);
    defer std.testing.allocator.free(cycles);

    try std.testing.expectEqual(@as(usize, 2), cycles.len);
    try std.testing.expectEqual(TimeSpan.init(Fraction.init(0, 1), Fraction.init(1, 1)), cycles[0]);
    try std.testing.expectEqual(TimeSpan.init(Fraction.init(1, 1), Fraction.init(2, 1)), cycles[1]);
}

test "span cycles partial" {
    const span = TimeSpan.init(Fraction.init(1, 2), Fraction.init(3, 2));
    const cycles = try span.spanCycles(std.testing.allocator);
    defer std.testing.allocator.free(cycles);

    try std.testing.expectEqual(@as(usize, 2), cycles.len);
    try std.testing.expectEqual(TimeSpan.init(Fraction.init(1, 2), Fraction.init(1, 1)), cycles[0]);
    try std.testing.expectEqual(TimeSpan.init(Fraction.init(1, 1), Fraction.init(3, 2)), cycles[1]);
}

test "with time and cycle helpers" {
    const span = TimeSpan.init(Fraction.init(1, 2), Fraction.init(3, 2));
    try std.testing.expectEqual(
        TimeSpan.init(Fraction.init(3, 2), Fraction.init(5, 2)),
        span.withTime(addOne),
    );

    try std.testing.expectEqual(
        TimeSpan.init(Fraction.init(1, 2), Fraction.init(5, 2)),
        span.withEnd(addOne),
    );

    try std.testing.expectEqual(
        TimeSpan.init(Fraction.init(1, 4), Fraction.init(3, 4)),
        span.withCycle(halfCycle),
    );
}

test "intersection" {
    const a = TimeSpan.init(Fraction.init(0, 1), Fraction.init(1, 1));
    const b = TimeSpan.init(Fraction.init(1, 2), Fraction.init(3, 2));
    const intersection = a.intersection(b);

    try std.testing.expect(intersection != null);
    try std.testing.expectEqual(
        TimeSpan.init(Fraction.init(1, 2), Fraction.init(1, 1)),
        intersection.?,
    );
}

test "intersection excludes touching open end" {
    const a = TimeSpan.init(Fraction.init(0, 1), Fraction.init(1, 1));
    const b = TimeSpan.init(Fraction.init(1, 1), Fraction.init(2, 1));

    try std.testing.expectEqual(@as(?TimeSpan, null), a.intersection(b));
}

test "intersection keeps zero-width overlap at interior boundary" {
    const point = TimeSpan.init(Fraction.init(1, 1), Fraction.init(1, 1));
    const span = TimeSpan.init(Fraction.init(1, 1), Fraction.init(2, 1));

    const intersection = point.intersection(span);
    try std.testing.expect(intersection != null);
    try std.testing.expectEqual(point, intersection.?);
}

test "no intersection" {
    const a = TimeSpan.init(Fraction.init(0, 1), Fraction.init(1, 2));
    const b = TimeSpan.init(Fraction.init(3, 4), Fraction.init(1, 1));

    try std.testing.expectEqual(@as(?TimeSpan, null), a.intersection(b));
}

test "duration" {
    const span = TimeSpan.init(Fraction.init(1, 4), Fraction.init(3, 4));
    try std.testing.expectEqual(Fraction.init(1, 2), span.duration());
}
