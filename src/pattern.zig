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

        pub fn clone(self: Self, allocator: std.mem.Allocator) std.mem.Allocator.Error!Self {
            return switch (self) {
                .silence => .silence,
                .pure => |value| .{ .pure = value },
                .stacked => |node| blk: {
                    var left = try node.left.clone(allocator);
                    errdefer left.deinit(allocator);
                    const right = try node.right.clone(allocator);
                    break :blk try left.stack(allocator, right);
                },
                .fast_t => |node| blk: {
                    var child = try node.pattern.clone(allocator);
                    errdefer child.deinit(allocator);
                    break :blk try child.fast(allocator, node.factor);
                },
                .slow_t => |node| blk: {
                    var child = try node.pattern.clone(allocator);
                    errdefer child.deinit(allocator);
                    break :blk try child.slow(allocator, node.factor);
                },
                .early_t => |node| blk: {
                    var child = try node.pattern.clone(allocator);
                    errdefer child.deinit(allocator);
                    break :blk try child.early(allocator, node.offset);
                },
                .rev_t => |node| blk: {
                    var child = try node.pattern.clone(allocator);
                    errdefer child.deinit(allocator);
                    break :blk try child.rev(allocator);
                },
                .fastcat_t => |node| fastcat(T, allocator, node.patterns),
                .slowcat_t => |node| slowcat(T, allocator, node.patterns),
            };
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

pub fn when(
    comptime T: type,
    allocator: std.mem.Allocator,
    n_cycles: i64,
    on_cycle: i64,
    transform: anytype,
    pat: Pattern(T),
) std.mem.Allocator.Error!Pattern(T) {
    if (n_cycles <= 0) return pat;

    const n: usize = @intCast(n_cycles);
    const idx_i64 = @mod(on_cycle, n_cycles);
    const idx: usize = @intCast(idx_i64);

    const slots = try allocator.alloc(Pattern(T), n);
    errdefer allocator.free(slots);

    var initialized: usize = 0;
    errdefer {
        for (slots[0..initialized]) |*slot| slot.deinit(allocator);
    }

    for (0..n) |i| {
        if (i == idx) {
            slots[i] = try transform(allocator, pat);
        } else {
            slots[i] = try pat.clone(allocator);
        }
        initialized += 1;
    }

    const out = try slowcat(T, allocator, slots);
    allocator.free(slots);
    return out;
}

pub fn first_of(comptime T: type, allocator: std.mem.Allocator, n_cycles: i64, transform: anytype, pat: Pattern(T)) std.mem.Allocator.Error!Pattern(T) {
    return when(T, allocator, n_cycles, 0, transform, pat);
}

pub fn last_of(comptime T: type, allocator: std.mem.Allocator, n_cycles: i64, transform: anytype, pat: Pattern(T)) std.mem.Allocator.Error!Pattern(T) {
    if (n_cycles <= 0) return pat;
    return when(T, allocator, n_cycles, n_cycles - 1, transform, pat);
}

pub fn every(comptime T: type, allocator: std.mem.Allocator, n_cycles: i64, transform: anytype, pat: Pattern(T)) std.mem.Allocator.Error!Pattern(T) {
    return first_of(T, allocator, n_cycles, transform, pat);
}

pub fn ply(comptime T: type, allocator: std.mem.Allocator, copies: i64, pat: Pattern(T)) std.mem.Allocator.Error!Pattern(T) {
    if (copies <= 1) return pat;

    const n: usize = @intCast(copies);
    const factor = Fraction.fromInteger(copies);

    var out = try (try pat.clone(allocator)).fast(allocator, factor);
    errdefer out.deinit(allocator);

    for (1..n) |i| {
        const offset = Fraction.init(@intCast(i), copies);
        var shifted = try (try pat.clone(allocator)).fast(allocator, factor);
        errdefer shifted.deinit(allocator);
        shifted = try shifted.late(allocator, offset);

        out = try out.stack(allocator, shifted);
    }

    return out;
}

pub fn superimpose(comptime T: type, allocator: std.mem.Allocator, left: Pattern(T), right: Pattern(T)) std.mem.Allocator.Error!Pattern(T) {
    return left.stack(allocator, right);
}

pub fn layer(comptime T: type, allocator: std.mem.Allocator, patterns: []const Pattern(T)) std.mem.Allocator.Error!Pattern(T) {
    if (patterns.len == 0) return silence(T);

    var out = try patterns[0].clone(allocator);
    errdefer out.deinit(allocator);

    for (patterns[1..]) |pat| {
        out = try out.stack(allocator, try pat.clone(allocator));
    }

    return out;
}

pub fn interleave(comptime T: type, allocator: std.mem.Allocator, patterns: []const Pattern(T)) std.mem.Allocator.Error!Pattern(T) {
    return fastcat(T, allocator, patterns);
}

pub fn timecat(
    comptime T: type,
    allocator: std.mem.Allocator,
    weights: []const Fraction,
    patterns: []const Pattern(T),
) std.mem.Allocator.Error!Pattern(T) {
    if (weights.len == 0 or patterns.len == 0 or weights.len != patterns.len) {
        return silence(T);
    }

    var total = Fraction.zero();
    for (weights) |w| {
        if (w.cmp(Fraction.zero()) != .gt) continue;
        total = total.add(w);
    }
    if (total.isZero()) return silence(T);

    var cursor = Fraction.zero();
    var out: ?Pattern(T) = null;
    errdefer if (out) |*pat| pat.deinit(allocator);

    for (weights, patterns) |w, pat| {
        if (w.cmp(Fraction.zero()) != .gt) continue;

        const span = w.div(total);

        var seg = try (try pat.clone(allocator)).slow(allocator, span);
        errdefer seg.deinit(allocator);
        seg = try seg.late(allocator, cursor);

        if (out) |existing| {
            out = try existing.stack(allocator, seg);
        } else {
            out = seg;
        }

        cursor = cursor.add(span);
    }

    return out orelse silence(T);
}

fn rotateLeftBool(values: []bool, by: usize) void {
    if (values.len <= 1) return;
    std.mem.rotate(bool, values, by % values.len);
}

fn bjorklund(allocator: std.mem.Allocator, pulses: usize, steps: usize) std.mem.Allocator.Error![]bool {
    if (steps == 0) return allocator.alloc(bool, 0);
    if (pulses >= steps) {
        const out = try allocator.alloc(bool, steps);
        @memset(out, true);
        return out;
    }
    if (pulses == 0) {
        const out = try allocator.alloc(bool, steps);
        @memset(out, false);
        return out;
    }

    var counts: std.ArrayListUnmanaged(usize) = .empty;
    defer counts.deinit(allocator);
    var remainders: std.ArrayListUnmanaged(usize) = .empty;
    defer remainders.deinit(allocator);

    try remainders.append(allocator, pulses);

    var divisor = steps - pulses;
    while (true) {
        const level_idx = remainders.items.len - 1;
        const rem = remainders.items[level_idx];
        try counts.append(allocator, @divTrunc(divisor, rem));
        try remainders.append(allocator, @mod(divisor, rem));

        divisor = rem;
        if (remainders.items[remainders.items.len - 1] <= 1) break;
    }
    try counts.append(allocator, divisor);

    var out: std.ArrayListUnmanaged(bool) = .empty;
    errdefer out.deinit(allocator);

    const Builder = struct {
        fn run(
            allocator_inner: std.mem.Allocator,
            counts_inner: []const usize,
            remainders_inner: []const usize,
            output: *std.ArrayListUnmanaged(bool),
            level: i64,
        ) std.mem.Allocator.Error!void {
            if (level == -1) {
                try output.append(allocator_inner, false);
                return;
            }
            if (level == -2) {
                try output.append(allocator_inner, true);
                return;
            }

            const idx: usize = @intCast(level);
            var i: usize = 0;
            while (i < counts_inner[idx]) : (i += 1) {
                try run(allocator_inner, counts_inner, remainders_inner, output, level - 1);
            }
            if (remainders_inner[idx] != 0) {
                try run(allocator_inner, counts_inner, remainders_inner, output, level - 2);
            }
        }
    };

    try Builder.run(allocator, counts.items, remainders.items, &out, @as(i64, @intCast(counts.items.len - 1)));
    std.debug.assert(out.items.len == steps);

    if (std.mem.indexOfScalar(bool, out.items, true)) |first_true| {
        rotateLeftBool(out.items, first_true);
    }

    return out.toOwnedSlice(allocator);
}

pub fn euclid(allocator: std.mem.Allocator, pulses: i64, steps: i64, value: anytype) std.mem.Allocator.Error!Pattern(@TypeOf(value)) {
    const T = @TypeOf(value);
    const steps_u: usize = if (steps <= 0) 0 else @intCast(steps);
    const pulses_u: usize = blk: {
        if (pulses <= 0) break :blk 0;
        if (steps_u == 0) break :blk 0;
        const p: usize = @intCast(pulses);
        break :blk @min(p, steps_u);
    };

    const bits = try bjorklund(allocator, pulses_u, steps_u);
    defer allocator.free(bits);

    const pats = try allocator.alloc(Pattern(T), bits.len);
    defer allocator.free(pats);

    for (bits, 0..) |is_pulse, i| {
        pats[i] = if (is_pulse) pure(value) else silence(T);
    }

    return fastcat(T, allocator, pats);
}

pub fn euclid_rot(allocator: std.mem.Allocator, pulses: i64, steps: i64, rotation: i64, value: anytype) std.mem.Allocator.Error!Pattern(@TypeOf(value)) {
    var pat = try euclid(allocator, pulses, steps, value);
    errdefer pat.deinit(allocator);

    if (steps <= 0) {
        return pat;
    }

    return pat.late(allocator, Fraction.init(rotation, steps));
}

fn sampledSignal(
    allocator: std.mem.Allocator,
    comptime sample_count: usize,
    comptime sampler: fn (phase: f64) f64,
) std.mem.Allocator.Error!Pattern(f64) {
    const pats = try allocator.alloc(Pattern(f64), sample_count);
    defer allocator.free(pats);

    for (pats, 0..) |*pat, i| {
        const phase = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(sample_count));
        pat.* = pure(sampler(phase));
    }

    return fastcat(f64, allocator, pats);
}

pub fn saw(allocator: std.mem.Allocator) std.mem.Allocator.Error!Pattern(f64) {
    return sampledSignal(allocator, 64, struct {
        fn at(phase: f64) f64 {
            return (2.0 * phase) - 1.0;
        }
    }.at);
}

pub fn sine(allocator: std.mem.Allocator) std.mem.Allocator.Error!Pattern(f64) {
    return sampledSignal(allocator, 64, struct {
        fn at(phase: f64) f64 {
            return std.math.sin((2.0 * std.math.pi) * phase);
        }
    }.at);
}

pub fn cosine(allocator: std.mem.Allocator) std.mem.Allocator.Error!Pattern(f64) {
    return sampledSignal(allocator, 64, struct {
        fn at(phase: f64) f64 {
            return std.math.cos((2.0 * std.math.pi) * phase);
        }
    }.at);
}

pub fn tri(allocator: std.mem.Allocator) std.mem.Allocator.Error!Pattern(f64) {
    return sampledSignal(allocator, 64, struct {
        fn at(phase: f64) f64 {
            return 1.0 - (4.0 * @abs(phase - 0.5));
        }
    }.at);
}

pub fn square(allocator: std.mem.Allocator) std.mem.Allocator.Error!Pattern(f64) {
    return sampledSignal(allocator, 64, struct {
        fn at(phase: f64) f64 {
            return if (phase < 0.5) 1.0 else -1.0;
        }
    }.at);
}

pub fn range(allocator: std.mem.Allocator, min: f64, max: f64) std.mem.Allocator.Error!Pattern(f64) {
    const samples: usize = 64;
    const pats = try allocator.alloc(Pattern(f64), samples);
    defer allocator.free(pats);

    const delta = max - min;
    for (pats, 0..) |*pat, i| {
        const phase = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(samples));
        pat.* = pure(min + (delta * phase));
    }

    return fastcat(f64, allocator, pats);
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

test "phase2a parity: first_of transforms first cycle in each window" {
    var pat = try first_of(u8, std.testing.allocator, 2, struct {
        fn apply(allocator: std.mem.Allocator, p: Pattern(u8)) std.mem.Allocator.Error!Pattern(u8) {
            return p.rev(allocator);
        }
    }.apply, try sequence(u8, std.testing.allocator, &[_]Pattern(u8){ pure(@as(u8, 1)), pure(@as(u8, 2)) }));
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.queryArc(std.testing.allocator, Fraction.zero(), Fraction.fromInteger(2));
    defer std.testing.allocator.free(haps);

    std.sort.heap(Hap(u8), haps, {}, struct {
        fn lessThan(_: void, a: Hap(u8), b: Hap(u8)) bool {
            return a.part.begin.cmp(b.part.begin) == .lt;
        }
    }.lessThan);

    try std.testing.expectEqual(@as(usize, 4), haps.len);
    try std.testing.expectEqual(@as(u8, 2), haps[0].value);
    try std.testing.expectEqual(@as(u8, 1), haps[1].value);
    try std.testing.expectEqual(@as(u8, 1), haps[2].value);
    try std.testing.expectEqual(@as(u8, 2), haps[3].value);
}

test "phase2a parity: every aliases first_of semantics" {
    var via_every = try every(u8, std.testing.allocator, 2, struct {
        fn apply(allocator: std.mem.Allocator, p: Pattern(u8)) std.mem.Allocator.Error!Pattern(u8) {
            return p.rev(allocator);
        }
    }.apply, try sequence(u8, std.testing.allocator, &[_]Pattern(u8){ pure(@as(u8, 1)), pure(@as(u8, 2)) }));
    defer via_every.deinit(std.testing.allocator);

    var via_first_of = try first_of(u8, std.testing.allocator, 2, struct {
        fn apply(allocator: std.mem.Allocator, p: Pattern(u8)) std.mem.Allocator.Error!Pattern(u8) {
            return p.rev(allocator);
        }
    }.apply, try sequence(u8, std.testing.allocator, &[_]Pattern(u8){ pure(@as(u8, 1)), pure(@as(u8, 2)) }));
    defer via_first_of.deinit(std.testing.allocator);

    const every_haps = try via_every.queryArc(std.testing.allocator, Fraction.zero(), Fraction.fromInteger(2));
    defer std.testing.allocator.free(every_haps);
    const first_haps = try via_first_of.queryArc(std.testing.allocator, Fraction.zero(), Fraction.fromInteger(2));
    defer std.testing.allocator.free(first_haps);

    std.sort.heap(Hap(u8), every_haps, {}, struct {
        fn lessThan(_: void, a: Hap(u8), b: Hap(u8)) bool {
            return a.part.begin.cmp(b.part.begin) == .lt;
        }
    }.lessThan);
    std.sort.heap(Hap(u8), first_haps, {}, struct {
        fn lessThan(_: void, a: Hap(u8), b: Hap(u8)) bool {
            return a.part.begin.cmp(b.part.begin) == .lt;
        }
    }.lessThan);

    try std.testing.expectEqual(@as(usize, first_haps.len), every_haps.len);
    for (every_haps, first_haps) |left, right| {
        try std.testing.expectEqual(left.value, right.value);
        try std.testing.expectEqual(left.part.begin, right.part.begin);
        try std.testing.expectEqual(left.part.end, right.part.end);
    }
}

test "phase2a parity: ply triples density for pure source" {
    var pat = try ply(u8, std.testing.allocator, 3, pure(@as(u8, 7)));
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 9), haps.len);
}

test "phase2a parity: layer and superimpose stack values" {
    var layered = try layer(u8, std.testing.allocator, &[_]Pattern(u8){ pure(@as(u8, 1)), pure(@as(u8, 2)), pure(@as(u8, 3)) });
    defer layered.deinit(std.testing.allocator);

    const layer_haps = try layered.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(layer_haps);
    try std.testing.expectEqual(@as(usize, 3), layer_haps.len);
    try std.testing.expectEqual(@as(u8, 1), layer_haps[0].value);
    try std.testing.expectEqual(@as(u8, 2), layer_haps[1].value);
    try std.testing.expectEqual(@as(u8, 3), layer_haps[2].value);

    var over = try superimpose(u8, std.testing.allocator, pure(@as(u8, 10)), pure(@as(u8, 11)));
    defer over.deinit(std.testing.allocator);
    const over_haps = try over.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(over_haps);
    try std.testing.expectEqual(@as(usize, 2), over_haps.len);
    try std.testing.expectEqual(@as(u8, 10), over_haps[0].value);
    try std.testing.expectEqual(@as(u8, 11), over_haps[1].value);
}

test "phase2a parity: interleave matches fastcat segmentation" {
    const pats = [_]Pattern(u8){ pure(@as(u8, 4)), pure(@as(u8, 5)) };

    var int_pat = try interleave(u8, std.testing.allocator, &pats);
    defer int_pat.deinit(std.testing.allocator);
    var fc_pat = try fastcat(u8, std.testing.allocator, &pats);
    defer fc_pat.deinit(std.testing.allocator);

    const int_haps = try int_pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(int_haps);
    const fc_haps = try fc_pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(fc_haps);

    try std.testing.expectEqual(@as(usize, fc_haps.len), int_haps.len);
    for (int_haps, fc_haps) |left, right| {
        try std.testing.expectEqual(left.value, right.value);
        try std.testing.expectEqual(left.part.begin, right.part.begin);
        try std.testing.expectEqual(left.part.end, right.part.end);
    }
}

test "phase2a parity: timecat applies weighted slices and skips non-positive weights" {
    const weights = [_]Fraction{ Fraction.init(1, 1), Fraction.zero(), Fraction.init(3, 1), Fraction.init(-1, 1) };
    const pats = [_]Pattern(u8){ pure(@as(u8, 1)), pure(@as(u8, 99)), pure(@as(u8, 2)), pure(@as(u8, 88)) };
    var tc = try timecat(u8, std.testing.allocator, &weights, &pats);
    defer tc.deinit(std.testing.allocator);

    const tc_haps = try tc.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(tc_haps);

    std.sort.heap(Hap(u8), tc_haps, {}, struct {
        fn lessThan(_: void, a: Hap(u8), b: Hap(u8)) bool {
            return a.part.begin.cmp(b.part.begin) == .lt;
        }
    }.lessThan);

    try std.testing.expect(tc_haps.len >= 2);

    var seen_first = false;
    var seen_second = false;
    for (tc_haps) |hap| {
        try std.testing.expect(hap.value == 1 or hap.value == 2);
        if (hap.value == 1) seen_first = true;
        if (hap.value == 2) seen_second = true;
    }

    try std.testing.expect(seen_first);
    try std.testing.expect(seen_second);
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

test "utility saw stays in [-1,1) over first cycle" {
    var pat = try saw(std.testing.allocator);
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 64), haps.len);
    try std.testing.expectApproxEqAbs(@as(f64, -1.0), haps[0].value, 1e-9);
    try std.testing.expect(haps[63].value < 1.0);
    for (haps) |hap| {
        try std.testing.expect(hap.value >= -1.0);
        try std.testing.expect(hap.value < 1.0);
    }
}

test "utility sine and cosine stay within unit amplitude" {
    var sin_pat = try sine(std.testing.allocator);
    defer sin_pat.deinit(std.testing.allocator);
    var cos_pat = try cosine(std.testing.allocator);
    defer cos_pat.deinit(std.testing.allocator);

    const sin_haps = try sin_pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(sin_haps);
    const cos_haps = try cos_pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(cos_haps);

    try std.testing.expectEqual(@as(usize, 64), sin_haps.len);
    try std.testing.expectEqual(@as(usize, 64), cos_haps.len);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), sin_haps[0].value, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), cos_haps[0].value, 1e-9);

    for (sin_haps) |hap| {
        try std.testing.expect(hap.value >= -1.0 and hap.value <= 1.0);
    }
    for (cos_haps) |hap| {
        try std.testing.expect(hap.value >= -1.0 and hap.value <= 1.0);
    }
}

test "utility tri and square hit expected extrema" {
    var tri_pat = try tri(std.testing.allocator);
    defer tri_pat.deinit(std.testing.allocator);
    var sq_pat = try square(std.testing.allocator);
    defer sq_pat.deinit(std.testing.allocator);

    const tri_haps = try tri_pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(tri_haps);
    const sq_haps = try sq_pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(sq_haps);

    try std.testing.expectApproxEqAbs(@as(f64, -1.0), tri_haps[0].value, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), tri_haps[32].value, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), sq_haps[0].value, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, -1.0), sq_haps[32].value, 1e-9);
}

test "utility range ramps between provided bounds" {
    var pat = try range(std.testing.allocator, 10.0, 20.0);
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 64), haps.len);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), haps[0].value, 1e-9);
    try std.testing.expect(haps[63].value > 19.8 and haps[63].value < 20.0);
    for (haps, 1..) |hap, i| {
        try std.testing.expect(hap.value >= haps[i - 1].value);
    }
}

test "rust parity: test_bjorklund_algorithm" {
    const p3_8 = try bjorklund(std.testing.allocator, 3, 8);
    defer std.testing.allocator.free(p3_8);
    try std.testing.expectEqualSlices(bool, &[_]bool{ true, false, false, true, false, false, true, false }, p3_8);

    const p5_8 = try bjorklund(std.testing.allocator, 5, 8);
    defer std.testing.allocator.free(p5_8);
    try std.testing.expectEqualSlices(bool, &[_]bool{ true, false, true, true, false, true, true, false }, p5_8);

    const p4_12 = try bjorklund(std.testing.allocator, 4, 12);
    defer std.testing.allocator.free(p4_12);
    try std.testing.expectEqualSlices(bool, &[_]bool{ true, false, false, true, false, false, true, false, false, true, false, false }, p4_12);
}

test "rust parity: test_euclid and edge cases" {
    var pat = try euclid(std.testing.allocator, 3, 8, @as(i32, 1));
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);
    try std.testing.expectEqual(@as(usize, 3), haps.len);

    var zero = try euclid(std.testing.allocator, 0, 8, @as(i32, 1));
    defer zero.deinit(std.testing.allocator);
    const zero_haps = try zero.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(zero_haps);
    try std.testing.expectEqual(@as(usize, 0), zero_haps.len);

    var full = try euclid(std.testing.allocator, 8, 8, @as(i32, 1));
    defer full.deinit(std.testing.allocator);
    const full_haps = try full.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(full_haps);
    try std.testing.expectEqual(@as(usize, 8), full_haps.len);
}

test "rust parity: test_euclid_positions and rotation" {
    var pat = try euclid(std.testing.allocator, 3, 8, @as([]const u8, "a"));
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    std.sort.heap(Hap([]const u8), haps, {}, struct {
        fn lessThan(_: void, a: Hap([]const u8), b: Hap([]const u8)) bool {
            return a.part.begin.cmp(b.part.begin) == .lt;
        }
    }.lessThan);

    try std.testing.expectEqual(@as(usize, 3), haps.len);
    try std.testing.expectEqual(Fraction.zero(), haps[0].part.begin);
    try std.testing.expectEqual(Fraction.init(3, 8), haps[1].part.begin);
    try std.testing.expectEqual(Fraction.init(3, 4), haps[2].part.begin);

    var rotated = try euclid_rot(std.testing.allocator, 3, 8, 1, @as(i32, 9));
    defer rotated.deinit(std.testing.allocator);
    const rotated_haps = try rotated.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(rotated_haps);

    std.sort.heap(Hap(i32), rotated_haps, {}, struct {
        fn lessThan(_: void, a: Hap(i32), b: Hap(i32)) bool {
            return a.part.begin.cmp(b.part.begin) == .lt;
        }
    }.lessThan);

    try std.testing.expectEqual(@as(usize, 3), rotated_haps.len);
    try std.testing.expectEqual(Fraction.init(1, 8), rotated_haps[0].part.begin);
    try std.testing.expectEqual(Fraction.init(1, 2), rotated_haps[1].part.begin);
    try std.testing.expectEqual(Fraction.init(7, 8), rotated_haps[2].part.begin);
}

test "rust parity: test_euclid_5_8_positions" {
    var pat = try euclid(std.testing.allocator, 5, 8, @as([]const u8, "a"));
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);
    try std.testing.expectEqual(@as(usize, 5), haps.len);
}

test "rust parity: test_signal_range" {
    var saw_pat = try saw(std.testing.allocator);
    defer saw_pat.deinit(std.testing.allocator);
    const saw_haps = try saw_pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(saw_haps);
    try std.testing.expectEqual(@as(usize, 64), saw_haps.len);
    for (saw_haps) |hap| {
        try std.testing.expect(hap.value >= -1.0 and hap.value < 1.0);
    }

    var sine_pat = try sine(std.testing.allocator);
    defer sine_pat.deinit(std.testing.allocator);
    const sine_haps = try sine_pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(sine_haps);
    try std.testing.expectEqual(@as(usize, 64), sine_haps.len);
    for (sine_haps) |hap| {
        try std.testing.expect(hap.value >= -1.0 and hap.value <= 1.0);
    }

    var tri_pat = try tri(std.testing.allocator);
    defer tri_pat.deinit(std.testing.allocator);
    const tri_haps = try tri_pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(tri_haps);
    try std.testing.expectEqual(@as(usize, 64), tri_haps.len);
    for (tri_haps) |hap| {
        try std.testing.expect(hap.value >= -1.0 and hap.value <= 1.0);
    }

    var square_pat = try square(std.testing.allocator);
    defer square_pat.deinit(std.testing.allocator);
    const square_haps = try square_pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(square_haps);
    try std.testing.expectEqual(@as(usize, 64), square_haps.len);
    for (square_haps) |hap| {
        try std.testing.expect(hap.value == -1.0 or hap.value == 1.0);
    }
}

test "rust parity: test_range_scaling" {
    var pat = try range(std.testing.allocator, 100.0, 200.0);
    defer pat.deinit(std.testing.allocator);

    const haps = try pat.firstCycle(std.testing.allocator);
    defer std.testing.allocator.free(haps);

    try std.testing.expectEqual(@as(usize, 64), haps.len);
    for (haps) |hap| {
        try std.testing.expect(hap.value >= 100.0 and hap.value < 200.0);
    }
}
