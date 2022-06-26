const std = @import("std");
const goal = @import("goal.zig");
const state = @import("state.zig");
const globals = @import("globals.zig");

pub const StreamOptErrorUnion = std.fmt.AllocPrintError!?*const Stream;

pub const Stream = struct {
    advanceStreamOpt: ?fn () StreamOptErrorUnion = null,
    state_opt: ?state.State = null,

    pub fn unroll(self: *const Stream, states_slice: []state.State, num_states: usize) std.fmt.AllocPrintError!?[]state.State {
        if (num_states == 0) return null;
        const next_stream_opt = if (self.advanceStreamOpt) |advanceStream| try advanceStream() else null;
        if (self.state_opt) |state_| {
            var new_states_slice = blk: {
                if (next_stream_opt) |next_stream| {
                    break :blk (try next_stream.unroll(states_slice, num_states - 1)) orelse states_slice;
                } else {
                    break :blk states_slice;
                }
            };
            new_states_slice.len += 1;
            new_states_slice[new_states_slice.len - 1] = state_;
            return new_states_slice;
        } else {
            return if (next_stream_opt) |next_stream| try next_stream.unroll(states_slice, num_states) else null;
        }
    }

    pub fn format(self: *const Stream, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        try writer.writeAll("(");

        var stream: *const Stream = undefined;
        if (self.state_opt != null or self.advanceStreamOpt != null) {
            stream = self;
        } else {
            try writer.writeAll(")");
            return {};
        }

        while (true) {
            if (stream.state_opt) |state_| {
                try state_.format(fmt, options, writer);
                if (stream.advanceStreamOpt) |advanceStream| {
                    if (advanceStream() catch unreachable) |next_stream| {
                        stream = next_stream;
                    } else {
                        try writer.writeAll(")");
                        break;
                    }
                    try writer.writeAll(" ");
                } else {
                    try writer.writeAll(")");
                    break;
                }
            }
        }
    }
};

// TODO:
// Implement with Closure type from closure.zig
pub const MplusClosure = struct {
    var next_stream1_opt: ?*const Stream = undefined;
    var stream2_opt: ?*const Stream = undefined;

    pub fn func1() StreamOptErrorUnion {
        return Mplus(next_stream1_opt, stream2_opt);
    }

    pub fn func2() StreamOptErrorUnion {
        return Mplus(stream2_opt, next_stream1_opt);
    }
};

pub fn Mplus(stream1_opt: ?*const Stream, stream2_opt: ?*const Stream) StreamOptErrorUnion {
    if (stream1_opt) |stream1| {
        MplusClosure.next_stream1_opt = if (stream1.advanceStreamOpt) |advanceStream| try advanceStream() else null;
        MplusClosure.stream2_opt = stream2_opt;
        if (stream1.state_opt) |state_| {
            if (state_.isEqual(state.State{})) {
                return Suspension(MplusClosure.func2);
            } else {
                globals.STREAMS[globals.CUR_NUM_STATES] = .{ .state_opt = state_, .advanceStreamOpt = MplusClosure.func1 };
                defer globals.CUR_NUM_STATES += 1;
                return &globals.STREAMS[globals.CUR_NUM_STATES];
            }
        } else {
            return Suspension(MplusClosure.func2);
        }
    } else {
        return stream2_opt;
    }
}

// TODO:
// Implement with Closure type from closure.zig
pub const ZzzClosure = struct {
    var state_: state.State = undefined;
    var goal_: goal.Goal = undefined;

    pub fn func() StreamOptErrorUnion {
        return try goal_(state_);
    }

    pub fn goalFunc(state__: state.State) StreamOptErrorUnion {
        state_ = state__;
        return Suspension(func);
    }
};

pub fn Zzz(goal_: goal.Goal) goal.Goal {
    ZzzClosure.goal_ = goal_;
    return ZzzClosure.goalFunc;
}

pub fn Infinity(state_: state.State, advanceStreamOpt: ?fn () StreamOptErrorUnion) *const Stream {
    globals.STREAMS[globals.CUR_NUM_STATES] = .{ .state_opt = state_, .advanceStreamOpt = advanceStreamOpt };
    defer globals.CUR_NUM_STATES += 1;
    return &globals.STREAMS[globals.CUR_NUM_STATES];
}

pub fn Suspension(advanceStreamOpt: ?fn () StreamOptErrorUnion) *const Stream {
    globals.STREAMS[globals.CUR_NUM_STATES] = .{ .state_opt = .{}, .advanceStreamOpt = advanceStreamOpt };
    defer globals.CUR_NUM_STATES += 1;
    return &globals.STREAMS[globals.CUR_NUM_STATES];
}

pub fn Singleton(state_: state.State) *const Stream {
    globals.STREAMS[globals.CUR_NUM_STATES] = .{ .state_opt = state_ };
    defer globals.CUR_NUM_STATES += 1;
    return &globals.STREAMS[globals.CUR_NUM_STATES];
}

pub fn Void() *const Stream {
    globals.STREAMS[globals.CUR_NUM_STATES] = .{};
    defer globals.CUR_NUM_STATES += 1;
    return &globals.STREAMS[globals.CUR_NUM_STATES];
}
