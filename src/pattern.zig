const std = @import("std");
const Fraction = @import("fraction.zig").Fraction;
const Hap = @import("hap.zig").Hap;
const State = @import("state.zig").State;
const TimeSpan = @import("timespan.zig").TimeSpan;

pub fn Pattern(comptime T: type) type {
    return union(enum) {
        silence,
        pure: T,
        stacked: *StackNode,
        fast_t: *FastNode,
        slow_t: *SlowNode,
        early_t: *ShiftNode,
        rev_t: *RevNode,
        fastcat_t: *CatNode,
        slowcat_t: *CatNode,

        const Self = @This();

        const StackNode = struct {
            left: Self,
            right: Self,
        };

        const FastNode = struct {
            pattern: Self,
            factor: Fraction,
        };

        const SlowNode = struct {
            pattern: Self,
            factor: Fraction,
        };

        const ShiftNode = struct {
            pattern: Self,
            offset: Fraction,
        };

        const RevNode = struct {
            pattern: Self,
        };

        const CatNode = struct {
            patterns: []Self,
        };

        fn copyPatterns(allocator: std.mem.Allocator, patterns: []const Self) ![]Self {
            const out = try allocator.alloc(Self, patterns.len);
            @memcpy(out, patterns);
            return out;
        }

        fn appendHaps(list: *std.ArrayListUnmanaged(Hap(T)), allocator: std.mem.Allocator, haps: []const Hap(T)) !void {
            const old_len = list.items.len;
            try list.resize(allocator, old_len + haps.len);
            @memcpy(list.items[old_len..], haps);
        }

        fn shiftFraction(v: Fraction, by: Fraction) Fraction {
            return v.add(by);
        }

        fn reflectInCycle(span: TimeSpan, cycle_start: Fraction, cycle_end: Fraction) TimeSpan {
            return .{
                .begin = cycle_start.add(cycle_end.sub(span.end)),
                .end = cycle_start.add(cycle_end.sub(span.begin)),
            };
        }

        fn runFast(allocator: std.mem.Allocator, node: *const FastNode, state: State) std.mem.Allocator.Error![]Hap(T) {
            const child_state = state.setSpan(.{
                .begin = state.span.begin.mul(node.factor),
                .end = state.span.end.mul(node.factor),
            });
            const child = try node.pattern.query(allocator, child_state);
            errdefer allocator.free(child);

            for (child) |*hap| {
                hap.* = .{
                    .whole = if (hap.whole) |w| .{ .begin = w.begin.div(node.factor), .end = w.end.div(node.factor) } else null,
                    .part = .{ .begin = hap.part.begin.div(node.factor), .end = hap.part.end.div(node.factor) },
                    .value = hap.value,
                    .context = hap.context,
                };
            }
            return child;
        }

        fn runSlow(allocator: std.mem.Allocator, node: *const SlowNode, state: State) std.mem.Allocator.Error![]Hap(T) {
            const child_state = state.setSpan(.{
                .begin = state.span.begin.div(node.factor),
                .end = state.span.end.div(node.factor),
            });
            const child = try node.pattern.query(allocator, child_state);
            errdefer allocator.free(child);

            for (child) |*hap| {
                hap.* = .{
                    .whole = if (hap.whole) |w| .{ .begin = w.begin.mul(node.factor), .end = w.end.mul(node.factor) } else null,
                    .part = .{ .begin = hap.part.begin.mul(node.factor), .end = hap.part.end.mul(node.factor) },
                    .value = hap.value,
                    .context = hap.context,
                };
            }
            return child;
        }

        fn runEarly(allocator: std.mem.Allocator, node: *const ShiftNode, state: State) std.mem.Allocator.Error![]Hap(T) {
            const shifted = state.setSpan(.{
                .begin = shiftFraction(state.span.begin, node.offset),
                .end = shiftFraction(state.span.end, node.offset),
            });
            const child = try node.pattern.query(allocator, shifted);
            errdefer allocator.free(child);

            for (child) |*hap| {
                hap.* = .{
                    .whole = if (hap.whole) |w| .{ .begin = w.begin.sub(node.offset), .end = w.end.sub(node.offset) } else null,
                    .part = .{ .begin = hap.part.begin.sub(node.offset), .end = hap.part.end.sub(node.offset) },
                    .value = hap.value,
                    .context = hap.context,
                };
            }
            return child;
        }

        fn runRev(allocator: std.mem.Allocator, node: *const RevNode, state: State) std.mem.Allocator.Error![]Hap(T) {
            const cycles = try state.span.spanCycles(allocator);
            defer allocator.free(cycles);

            var out: std.ArrayListUnmanaged(Hap(T)) = .empty;
            errdefer out.deinit(allocator);

            for (cycles) |cycle_span| {
                const cycle_start = cycle_span.begin.sam();
                const cycle_end = cycle_start.add(Fraction.one());

                const reflected_query = reflectInCycle(cycle_span, cycle_start, cycle_end);
                const child = try node.pattern.query(allocator, state.setSpan(reflected_query));
                defer allocator.free(child);

                for (child) |*hap| {
                    hap.* = .{
                        .whole = if (hap.whole) |w| reflectInCycle(w, cycle_start, cycle_end) else null,
                        .part = reflectInCycle(hap.part, cycle_start, cycle_end),
                        .value = hap.value,
                        .context = hap.context,
                    };
                }

                try appendHaps(&out, allocator, child);
            }

            return out.toOwnedSlice(allocator);
        }

        fn runFastCat(allocator: std.mem.Allocator, node: *const CatNode, state: State) std.mem.Allocator.Error![]Hap(T) {
            if (node.patterns.len == 0) {
                return allocator.alloc(Hap(T), 0);
            }

            const cycles = try state.span.spanCycles(allocator);
            defer allocator.free(cycles);

            var out: std.ArrayListUnmanaged(Hap(T)) = .empty;
            errdefer out.deinit(allocator);

            const n_frac = Fraction.fromInteger(@intCast(node.patterns.len));

            for (cycles) |cycle_span| {
                const cycle_start = cycle_span.begin.sam();
                const cycle_end = cycle_start.add(Fraction.one());

                for (node.patterns, 0..) |pat, idx| {
                    const i_frac = Fraction.fromInteger(@intCast(idx));
                    const j_frac = Fraction.fromInteger(@intCast(idx + 1));

                    const seg = TimeSpan.init(
                        cycle_start.add(i_frac.div(n_frac)),
                        cycle_start.add(j_frac.div(n_frac)),
                    );

                    const clipped = seg.intersection(TimeSpan.init(cycle_span.begin, cycle_end)) orelse continue;
                    const q_state = state.setSpan(clipped);
                    const haps = try pat.query(allocator, q_state);
                    defer allocator.free(haps);
                    try appendHaps(&out, allocator, haps);
                }
            }

            return out.toOwnedSlice(allocator);
        }

        fn runSlowCat(allocator: std.mem.Allocator, node: *const CatNode, state: State) std.mem.Allocator.Error![]Hap(T) {
            if (node.patterns.len == 0) {
                return allocator.alloc(Hap(T), 0);
            }

            const cycles = try state.span.spanCycles(allocator);
            defer allocator.free(cycles);

            var out: std.ArrayListUnmanaged(Hap(T)) = .empty;
            errdefer out.deinit(allocator);

            for (cycles) |cycle_span| {
                const cycle_index = @mod(cycle_span.begin.sam().numer, @as(i64, @intCast(node.patterns.len)));
                const pat = node.patterns[@intCast(cycle_index)];
                const haps = try pat.query(allocator, state.setSpan(cycle_span));
                defer allocator.free(haps);
                try appendHaps(&out, allocator, haps);
            }

            return out.toOwnedSlice(allocator);
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            switch (self.*) {
                .stacked => |node| {
                    node.left.deinit(allocator);
                    node.right.deinit(allocator);
                    allocator.destroy(node);
                },
                .fast_t => |node| {
                    node.pattern.deinit(allocator);
                    allocator.destroy(node);
                },
                .slow_t => |node| {
                    node.pattern.deinit(allocator);
                    allocator.destroy(node);
                },
                .early_t => |node| {
                    node.pattern.deinit(allocator);
                    allocator.destroy(node);
                },
                .rev_t => |node| {
                    node.pattern.deinit(allocator);
                    allocator.destroy(node);
                },
                .fastcat_t => |node| {
                    for (node.patterns) |*pat| pat.deinit(allocator);
                    allocator.free(node.patterns);
                    allocator.destroy(node);
                },
                .slowcat_t => |node| {
                    for (node.patterns) |*pat| pat.deinit(allocator);
                    allocator.free(node.patterns);
                    allocator.destroy(node);
                },
                else => {},
            }
            self.* = .silence;
        }

        pub fn query(self: Self, allocator: std.mem.Allocator, state: State) std.mem.Allocator.Error![]Hap(T) {
            switch (self) {
                .silence => return allocator.alloc(Hap(T), 0),
                .pure => |value| {
                    const cycles = try state.span.spanCycles(allocator);
                    defer allocator.free(cycles);

                    const out = try allocator.alloc(Hap(T), cycles.len);
                    for (cycles, 0..) |subspan, i| {
                        const whole = subspan.begin.wholeCycle();
                        out[i] = Hap(T).init(TimeSpan.init(whole.begin, whole.end), subspan, value);
                    }
                    return out;
                },
                .stacked => |node| {
                    const left = try node.left.query(allocator, state);
                    defer allocator.free(left);

                    const right = try node.right.query(allocator, state);
                    defer allocator.free(right);

                    const out = try allocator.alloc(Hap(T), left.len + right.len);
                    @memcpy(out[0..left.len], left);
                    @memcpy(out[left.len..], right);
                    return out;
                },
                .fast_t => |node| return runFast(allocator, node, state),
                .slow_t => |node| return runSlow(allocator, node, state),
                .early_t => |node| return runEarly(allocator, node, state),
                .rev_t => |node| return runRev(allocator, node, state),
                .fastcat_t => |node| return runFastCat(allocator, node, state),
                .slowcat_t => |node| return runSlowCat(allocator, node, state),
            }
        }

        pub fn queryArc(self: Self, allocator: std.mem.Allocator, begin: Fraction, end: Fraction) std.mem.Allocator.Error![]Hap(T) {
            const state = State.init(TimeSpan.init(begin, end));
            return self.query(allocator, state);
        }

        pub fn firstCycle(self: Self, allocator: std.mem.Allocator) std.mem.Allocator.Error![]Hap(T) {
            return self.queryArc(allocator, Fraction.zero(), Fraction.one());
        }

        pub fn stack(self: Self, allocator: std.mem.Allocator, other: Self) std.mem.Allocator.Error!Self {
            const node = try allocator.create(StackNode);
            node.* = .{ .left = self, .right = other };
            return .{ .stacked = node };
        }

        pub fn fast(self: Self, allocator: std.mem.Allocator, factor: Fraction) std.mem.Allocator.Error!Self {
            const node = try allocator.create(FastNode);
            node.* = .{ .pattern = self, .factor = factor };
            return .{ .fast_t = node };
        }

        pub fn slow(self: Self, allocator: std.mem.Allocator, factor: Fraction) std.mem.Allocator.Error!Self {
            const node = try allocator.create(SlowNode);
            node.* = .{ .pattern = self, .factor = factor };
            return .{ .slow_t = node };
        }

        pub fn early(self: Self, allocator: std.mem.Allocator, offset: Fraction) std.mem.Allocator.Error!Self {
            const node = try allocator.create(ShiftNode);
            node.* = .{ .pattern = self, .offset = offset };
            return .{ .early_t = node };
        }

        pub fn late(self: Self, allocator: std.mem.Allocator, offset: Fraction) std.mem.Allocator.Error!Self {
            return self.early(allocator, offset.neg());
        }

        pub fn rev(self: Self, allocator: std.mem.Allocator) std.mem.Allocator.Error!Self {
            const node = try allocator.create(RevNode);
            node.* = .{ .pattern = self };
            return .{ .rev_t = node };
        }
    };
}

pub fn silence(comptime T: type) Pattern(T) {
    return .silence;
}

pub fn pure(value: anytype) Pattern(@TypeOf(value)) {
    return .{ .pure = value };
}

pub fn fastcat(comptime T: type, allocator: std.mem.Allocator, patterns: []const Pattern(T)) std.mem.Allocator.Error!Pattern(T) {
    const node = try allocator.create(Pattern(T).CatNode);
    node.* = .{ .patterns = try Pattern(T).copyPatterns(allocator, patterns) };
    return .{ .fastcat_t = node };
}

pub fn sequence(comptime T: type, allocator: std.mem.Allocator, patterns: []const Pattern(T)) std.mem.Allocator.Error!Pattern(T) {
    return fastcat(T, allocator, patterns);
}

pub fn cat(comptime T: type, allocator: std.mem.Allocator, patterns: []const Pattern(T)) std.mem.Allocator.Error!Pattern(T) {
    return slowcat(T, allocator, patterns);
}

pub fn slowcat(comptime T: type, allocator: std.mem.Allocator, patterns: []const Pattern(T)) std.mem.Allocator.Error!Pattern(T) {
    const node = try allocator.create(Pattern(T).CatNode);
    node.* = .{ .patterns = try Pattern(T).copyPatterns(allocator, patterns) };
    return .{ .slowcat_t = node };
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

test "stack combines events from both patterns" {
    var pat = try pure(@as(u8, 2)).stack(std.testing.allocator, pure(@as(u8, 9)));
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 2), haps.len);
    try std.testing.expectEqual(@as(u8, 2), haps[0].value);
    try std.testing.expectEqual(@as(u8, 9), haps[1].value);
}

test "fast doubles event count over first cycle" {
    var pat = try pure(@as(u8, 1)).fast(std.testing.allocator, Fraction.fromInteger(2));
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 2), haps.len);
}

test "slow halves event count over two cycles" {
    var pat = try pure(@as(u8, 1)).slow(std.testing.allocator, Fraction.fromInteger(2));
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.queryArc(std.testing.allocator, Fraction.zero(), Fraction.fromInteger(2));
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 1), haps.len);
}

test "early shifts query sampling earlier" {
    var pat = try pure(@as(u8, 5)).early(std.testing.allocator, Fraction.init(1, 4));
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expect(haps.len >= 1);
    for (haps) |hap| {
        try std.testing.expectEqual(@as(u8, 5), hap.value);
    }
}

test "late shifts query sampling later" {
    var pat = try pure(@as(u8, 5)).late(std.testing.allocator, Fraction.init(1, 4));
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expect(haps.len >= 1);
    for (haps) |hap| {
        try std.testing.expectEqual(@as(u8, 5), hap.value);
    }
}

test "fastcat splits cycle across patterns" {
    const patterns = [_]Pattern(u8){ pure(@as(u8, 1)), pure(@as(u8, 2)) };
    var pat = try fastcat(u8, std.testing.allocator, &patterns);
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 2), haps.len);
    try std.testing.expectEqual(Fraction.zero(), haps[0].part.begin);
    try std.testing.expectEqual(Fraction.init(1, 2), haps[0].part.end);
    try std.testing.expectEqual(Fraction.init(1, 2), haps[1].part.begin);
    try std.testing.expectEqual(Fraction.one(), haps[1].part.end);
}

test "slowcat alternates patterns per cycle" {
    const patterns = [_]Pattern(u8){ pure(@as(u8, 3)), pure(@as(u8, 9)) };
    var pat = try slowcat(u8, std.testing.allocator, &patterns);
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.queryArc(std.testing.allocator, Fraction.zero(), Fraction.fromInteger(2));
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 2), haps.len);
    try std.testing.expectEqual(@as(u8, 3), haps[0].value);
    try std.testing.expectEqual(@as(u8, 9), haps[1].value);
}

test "rust parity: test_sequence preserves value order" {
    const patterns = [_]Pattern(i32){ pure(@as(i32, 1)), pure(@as(i32, 2)), pure(@as(i32, 3)), pure(@as(i32, 4)) };
    var pat = try sequence(i32, std.testing.allocator, &patterns);
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 4), haps.len);
    try std.testing.expectEqual(@as(i32, 1), haps[0].value);
    try std.testing.expectEqual(@as(i32, 2), haps[1].value);
    try std.testing.expectEqual(@as(i32, 3), haps[2].value);
    try std.testing.expectEqual(@as(i32, 4), haps[3].value);
}

test "rust parity: test_slow_hap_whole span semantics" {
    var pat = try pure("a").slow(std.testing.allocator, Fraction.fromInteger(2));
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 1), haps.len);
    try std.testing.expectEqualStrings("a", haps[0].value);
    try std.testing.expect(haps[0].whole != null);
    try std.testing.expectEqual(Fraction.fromInteger(0), haps[0].whole.?.begin);
    try std.testing.expectEqual(Fraction.fromInteger(2), haps[0].whole.?.end);
    try std.testing.expectEqual(Fraction.fromInteger(0), haps[0].part.begin);
    try std.testing.expectEqual(Fraction.fromInteger(1), haps[0].part.end);
}

test "rust parity: test_rev reverses sequence by onset" {
    const patterns = [_]Pattern(i32){ pure(@as(i32, 1)), pure(@as(i32, 2)), pure(@as(i32, 3)), pure(@as(i32, 4)) };
    var pat = try (try sequence(i32, std.testing.allocator, &patterns)).rev(std.testing.allocator);
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    std.sort.heap(Hap(i32), haps, {}, struct {
        fn lessThan(_: void, a: Hap(i32), b: Hap(i32)) bool {
            return a.part.begin.cmp(b.part.begin) == .lt;
        }
    }.lessThan);

    try std.testing.expectEqual(@as(usize, 4), haps.len);
    try std.testing.expectEqual(@as(i32, 4), haps[0].value);
    try std.testing.expectEqual(@as(i32, 3), haps[1].value);
    try std.testing.expectEqual(@as(i32, 2), haps[2].value);
    try std.testing.expectEqual(@as(i32, 1), haps[3].value);
}

test "rust parity: test_slowcat_alternates wraps on cycle 2" {
    const patterns = [_]Pattern([]const u8){ pure(@as([]const u8, "a")), pure(@as([]const u8, "b")) };
    var pat = try slowcat([]const u8, std.testing.allocator, &patterns);
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.queryArc(std.testing.allocator, Fraction.fromInteger(0), Fraction.fromInteger(3));
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 3), haps.len);
    try std.testing.expectEqualStrings("a", haps[0].value);
    try std.testing.expectEqualStrings("b", haps[1].value);
    try std.testing.expectEqualStrings("a", haps[2].value);
}
