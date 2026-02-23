const TimeSpan = @import("timespan.zig").TimeSpan;

pub const ControlValue = union(enum) {
    float: f64,
    int: i64,
    string: []const u8,
    bool: bool,
};

pub const State = struct {
    span: TimeSpan,

    pub fn init(span: TimeSpan) State {
        return .{ .span = span };
    }

    pub fn setSpan(self: State, span: TimeSpan) State {
        _ = self;
        return .{ .span = span };
    }
};

test "state creation" {
    const span = TimeSpan.fromIntegers(0, 1);
    const state = State.init(span);
    try std.testing.expectEqual(span, state.span);
}

const std = @import("std");
