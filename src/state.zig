const std = @import("std");
const Fraction = @import("fraction.zig").Fraction;
const TimeSpan = @import("timespan.zig").TimeSpan;

pub const ControlValue = union(enum) {
    float: f64,
    int: i64,
    string: []const u8,
    bool: bool,
};

pub const Control = struct {
    key: []const u8,
    value: ControlValue,
};

pub const State = struct {
    span: TimeSpan,
    controls: []const Control = &.{},

    pub fn init(span: TimeSpan) State {
        return .{ .span = span, .controls = &.{} };
    }

    pub fn withControls(span: TimeSpan, controls: []const Control) State {
        return .{ .span = span, .controls = controls };
    }

    pub fn setSpan(self: State, span: TimeSpan) State {
        return .{ .span = span, .controls = self.controls };
    }

    pub fn withSpan(self: State, f: *const fn (TimeSpan) TimeSpan) State {
        return self.setSpan(f(self.span));
    }

    pub fn setControls(self: State, controls: []const Control) State {
        return .{ .span = self.span, .controls = controls };
    }

    pub fn addControl(self: State, allocator: std.mem.Allocator, key: []const u8, value: ControlValue) !State {
        const out = try allocator.alloc(Control, self.controls.len + 1);
        @memcpy(out[0..self.controls.len], self.controls);
        out[self.controls.len] = .{ .key = key, .value = value };
        return .{ .span = self.span, .controls = out };
    }

    pub fn getControl(self: State, key: []const u8) ?ControlValue {
        for (self.controls) |control| {
            if (std.mem.eql(u8, control.key, key)) {
                return control.value;
            }
        }
        return null;
    }
};

fn shiftOne(span: TimeSpan) TimeSpan {
    return span.withTime(addOne);
}

fn addOne(v: Fraction) Fraction {
    return v.add(Fraction.one());
}

test "state creation" {
    const span = TimeSpan.fromIntegers(0, 1);
    const state = State.init(span);
    try std.testing.expectEqual(span, state.span);
    try std.testing.expectEqual(@as(usize, 0), state.controls.len);
}

test "state with controls" {
    const span = TimeSpan.fromIntegers(0, 1);
    const controls = [_]Control{
        .{ .key = "gain", .value = .{ .float = 0.5 } },
    };

    const state = State.withControls(span, &controls);
    const gain = state.getControl("gain");
    try std.testing.expect(gain != null);
    try std.testing.expectEqual(@as(f64, 0.5), gain.?.float);
}

test "set span keeps controls" {
    const span = TimeSpan.fromIntegers(0, 1);
    const controls = [_]Control{
        .{ .key = "swing", .value = .{ .bool = true } },
    };

    const state = State.withControls(span, &controls);
    const next = state.setSpan(TimeSpan.fromIntegers(1, 2));
    try std.testing.expectEqual(@as(usize, 1), next.controls.len);
    try std.testing.expect(next.getControl("swing").?.bool);
}

test "with span transform" {
    const span = TimeSpan.fromIntegers(0, 1);
    const state = State.init(span);
    const shifted = state.withSpan(shiftOne);

    try std.testing.expectEqual(TimeSpan.fromIntegers(1, 2), shifted.span);
}

test "add control" {
    const span = TimeSpan.fromIntegers(0, 1);
    const state = State.init(span);

    const with_gain = try state.addControl(std.testing.allocator, "gain", .{ .float = 0.25 });
    defer std.testing.allocator.free(with_gain.controls);

    const gain = with_gain.getControl("gain");
    try std.testing.expect(gain != null);
    try std.testing.expectEqual(@as(f64, 0.25), gain.?.float);
}
