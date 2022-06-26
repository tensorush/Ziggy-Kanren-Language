const std = @import("std");
const ast = @import("ast.zig");
const reify = @import("reify.zig");
const state = @import("state.zig");
const stream = @import("stream.zig");
const globals = @import("globals.zig");

pub const Goal = fn (state: state.State) stream.StreamOptErrorUnion;

pub fn RunGoal(states_slice: []state.State, num_states: usize, goal: Goal) std.fmt.AllocPrintError![]state.State {
    const stream_opt = try goal(.{});
    var new_states_slice_opt = if (stream_opt) |stream_| try stream_.unroll(states_slice, num_states) else null;
    return new_states_slice_opt orelse states_slice;
}

pub fn Run(exprs_slice: []?*const ast.Expr, num_states: usize, func: fn (ast.Expr) Goal) std.fmt.AllocPrintError![]?*const ast.Expr {
    const stream_opt = try func(try ast.Def("v0"))(.{ .subs_opt = null, .num_vars = 1 });
    var states: [globals.MAX_NUM_STATES]state.State = undefined;
    var states_slice_opt = if (stream_opt) |stream_| try stream_.unroll(states[0..0], num_states) else null;
    return if (states_slice_opt) |states_slice| try reify.Reify(exprs_slice, states_slice) else exprs_slice;
}

// TODO:
// Complete implementing with Closure type from closure.zig

// pub fn Fresh(fresh_func: anytype) std.fmt.AllocPrintError!type {
//     const fresh_closure = closure.Closure(struct {
//         fn func(env: struct { fresh_func: fn (*const ast.Expr) Goal }, state: state.State) Goal {
//             const variable = ast.Def(try std.fmt.allocPrint(std.heap.page_allocator, "v{d}", .{state.num_vars}));
//             const new_state = state.State{ .subs_opt = state.subs_opt, .num_vars = state.num_vars + 1 };
//             return env.fresh_func(variable)(new_state);
//         }
//     }.func).init(.{ .fresh_func = fresh_func });
//     return fresh_closure;
// }

// test "Fresh" {
//     var states: [globals.MAX_NUM_STATES]state.State = undefined;
//     const fresh_func = struct {
//         fn func(ziguana: *const ast.Expr) Goal {
//             return EqualO(ast.Symbol("Ziggy"), ziguana);
//         }
//     }.func;
//     const states_slice = try RunGoal(states[0..0], 1, Fresh(fresh_func));
//     const actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{states_slice[0]});
//     try std.testing.expectEqualStrings("((,v0 . Ziggy) . 1)", actual);
// }

const FreshClosure = struct {
    var func: fn (*const ast.Expr) Goal = undefined;

    fn goalFunc(state_: state.State) stream.StreamOptErrorUnion {
        const variable = ast.Def(try std.fmt.allocPrint(std.heap.page_allocator, "v{d}", .{state_.num_vars}));
        const new_state = state.State{ .subs_opt = state_.subs_opt, .num_vars = state_.num_vars + 1 };
        return func(variable)(new_state);
    }
};

const FreshTestClosure = struct {
    fn func(ziguana: *const ast.Expr) Goal {
        return EqualO(ast.Symbol("Ziggy"), ziguana);
    }
};

pub fn Fresh(func: fn (*const ast.Expr) Goal) Goal {
    FreshClosure.func = func;
    return FreshClosure.goalFunc;
}

// TODO:
// Implement with Closure type from closure.zig
pub const DisjClosure = struct {
    var goal1: Goal = undefined;
    var goal2: Goal = undefined;

    pub fn goalFunc(state_: state.State) stream.StreamOptErrorUnion {
        const stream1_opt = try goal1(state_);
        const stream2_opt = try goal2(state_);
        return stream.Mplus(stream1_opt, stream2_opt);
    }
};

pub fn Disj(goal1: Goal, goal2: Goal) Goal {
    DisjClosure.goal1 = goal1;
    DisjClosure.goal2 = goal2;
    return DisjClosure.goalFunc;
}

// TODO:
// Implement with Closure type from closure.zig
pub const ConjClosure = struct {
    var goal1: Goal = undefined;
    var goal2: Goal = undefined;

    pub fn goalFunc(state_: state.State) stream.StreamOptErrorUnion {
        return Bind(try goal1(state_), goal2);
    }
};

pub fn Conj(goal1: Goal, goal2: Goal) Goal {
    ConjClosure.goal1 = goal1;
    ConjClosure.goal2 = goal2;
    return ConjClosure.goalFunc;
}

pub const BindClosure = struct {
    var next_stream_opt: ?*const stream.Stream = undefined;
    var goal: Goal = undefined;

    pub fn func() stream.StreamOptErrorUnion {
        return Bind(next_stream_opt, goal);
    }
};

pub fn Bind(stream_opt: ?*const stream.Stream, goal: Goal) stream.StreamOptErrorUnion {
    if (stream_opt) |stream_| {
        const next_stream_opt = if (stream_.advanceStreamOpt) |advanceStream| try advanceStream() else null;
        if (stream_.state_opt) |state_| {
            return stream.Mplus(try goal(state_), try Bind(next_stream_opt, goal));
        } else {
            BindClosure.next_stream_opt = next_stream_opt;
            BindClosure.goal = goal;
            return stream.Suspension(BindClosure.func);
        }
    } else {
        return null;
    }
}

// TODO:
// Implement with Closure type from closure.zig
const EqualOClosure = struct {
    var expr1: *const ast.Expr = undefined;
    var expr2: *const ast.Expr = undefined;

    pub fn goalFunc(state_: state.State) stream.StreamOptErrorUnion {
        const subs_opt = Unify(EqualOClosure.expr1, EqualOClosure.expr2, state_.subs_opt);
        if (subs_opt) |subs| {
            if (state_.subs_opt != null and subs.isEqual(state_.subs_opt.?)) {
                return stream.Singleton(.{});
            } else {
                return stream.Singleton(.{ .subs_opt = subs, .num_vars = state_.num_vars });
            }
        } else {
            return stream.Void();
        }
    }
};

pub fn EqualO(expr1: *const ast.Expr, expr2: *const ast.Expr) Goal {
    EqualOClosure.expr1 = expr1;
    EqualOClosure.expr2 = expr2;
    return EqualOClosure.goalFunc;
}

pub fn Unify(expr1_opt: ?*const ast.Expr, expr2_opt: ?*const ast.Expr, subs_opt: ?state.Substitutions) ?state.Substitutions {
    const sub_expr1 = if (ast.isVariable(expr1_opt)) |expr1| state.Walk(expr1, subs_opt) else expr1_opt.?;
    const sub_expr2 = if (ast.isVariable(expr2_opt)) |expr2| state.Walk(expr2, subs_opt) else expr2_opt.?;
    const is_var_sub_expr1 = ast.isVariable(sub_expr1);
    const is_var_sub_expr2 = ast.isVariable(sub_expr2);
    if (is_var_sub_expr1 != null and is_var_sub_expr2 != null and sub_expr1.isEqual(sub_expr2)) {
        return subs_opt;
    } else if (is_var_sub_expr1) |_| {
        return state.Exts(sub_expr1, sub_expr2, subs_opt);
    } else if (is_var_sub_expr2) |_| {
        return state.Exts(sub_expr2, sub_expr1, subs_opt);
    } else if (ast.isPair(sub_expr1) != null and ast.isPair(sub_expr2) != null) {
        const car_subs_opt = Unify(ast.Car(sub_expr1), ast.Car(sub_expr2), subs_opt);
        return if (car_subs_opt) |car_subs| Unify(ast.Cdr(sub_expr1), ast.Cdr(sub_expr2), car_subs) else null;
    } else if (sub_expr1.isEqual(sub_expr2)) {
        return subs_opt;
    } else {
        return null;
    }
}

// TODO:
// Implement with Closure type from closure.zig
const NeverOClosure = struct {
    var state_: state.State = undefined;

    pub fn func() stream.StreamOptErrorUnion {
        return NeverO(state_);
    }
};

pub fn AlwaysO(state_: state.State) stream.StreamOptErrorUnion {
    NeverOClosure.state_ = state_;
    return stream.Infinity(state_, NeverOClosure.func);
}

pub fn NeverO(state_: state.State) stream.StreamOptErrorUnion {
    NeverOClosure.state_ = state_;
    return stream.Suspension(NeverOClosure.func);
}

pub fn SuccessO(state_: state.State) stream.StreamOptErrorUnion {
    return stream.Singleton(state_);
}

pub fn FailureO(_: state.State) stream.StreamOptErrorUnion {
    return stream.Void();
}

test "FailureO" {
    const actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{try FailureO(.{})});
    try std.testing.expectEqualStrings("()", actual);
}

test "SuccessO" {
    const actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{try SuccessO(.{})});
    try std.testing.expectEqualStrings("((() . 0))", actual);
}

test "NeverO" {
    const stream_opt = try NeverO(.{});
    try std.testing.expectEqual(state.State{}, stream_opt.?.state_opt.?);
    try std.testing.expect(null != stream_opt.?.advanceStreamOpt);
}

test "AlwaysO" {
    const stream_opt = try AlwaysO(.{});
    const next_stream_opt = try stream_opt.?.advanceStreamOpt.?();
    const actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{next_stream_opt.?.state_opt.?});
    try std.testing.expectEqualStrings("(() . 0)", actual);
    try std.testing.expectEqual(state.State{}, stream_opt.?.state_opt.?);
    try std.testing.expect(null != next_stream_opt.?.advanceStreamOpt);
}

test "EqualO" {
    const neo = ast.Int(1);
    const zero = ast.Int(0);
    var actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{EqualO(neo, neo)(.{ .subs_opt = .{} })});
    try std.testing.expectEqualStrings("((() . 0))", actual);
    actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{EqualO(neo, zero)(.{})});
    try std.testing.expectEqualStrings("()", actual);
}

test "Conj" {
    const x = ast.Def("x");
    const ziggy = ast.Symbol("Ziggy");
    const kanren = ast.Symbol("Kanren");

    var states: [globals.MAX_NUM_STATES]state.State = undefined;
    var states_slice = try RunGoal(states[0..0], 5, Conj(EqualO(ziggy, x), EqualO(kanren, x)));
    try std.testing.expect(0 == states_slice.len);

    states = undefined;
    states_slice = try RunGoal(states[0..0], 5, Conj(EqualO(ziggy, x), EqualO(ziggy, x)));
    var actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{states[0]});
    try std.testing.expectEqualStrings("((,x . Ziggy) . 0)", actual);
}

test "Disj" {
    var stream_opt = try Disj(EqualO(ast.Symbol("Ziggy"), ast.Def("x")), NeverO)(.{});
    var actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{stream_opt.?.state_opt.?});
    try std.testing.expectEqualStrings("((,x . Ziggy) . 0)", actual);
    try std.testing.expect(null != stream_opt.?.advanceStreamOpt);

    stream_opt = try Disj(NeverO, EqualO(ast.Symbol("Ziggy"), ast.Def("x")))(.{});
    try std.testing.expectEqual(state.State{}, stream_opt.?.state_opt.?);
    const next_stream_opt = try stream_opt.?.advanceStreamOpt.?();
    actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{next_stream_opt.?.state_opt.?});
    try std.testing.expectEqualStrings("((,x . Ziggy) . 0)", actual);
    try std.testing.expect(null != next_stream_opt.?.advanceStreamOpt);
}

test "Fresh" {
    var states: [globals.MAX_NUM_STATES]state.State = undefined;
    const states_slice = try RunGoal(states[0..0], 1, Fresh(FreshTestClosure.func));
    const actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{states_slice[0]});
    try std.testing.expectEqualStrings("((,v0 . Ziggy) . 1)", actual);
}

test "RunGoal" {
    var states: [globals.MAX_NUM_STATES]state.State = undefined;
    var states_slice = try RunGoal(states[0..0], 3, AlwaysO);
    var actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{states_slice[0]});
    try std.testing.expectEqualStrings("(() . 0)", actual);
    actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{states_slice[1]});
    try std.testing.expectEqualStrings("(() . 0)", actual);
    actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{states_slice[2]});
    try std.testing.expectEqualStrings("(() . 0)", actual);

    const x = ast.Def("x");
    const ziggy = ast.Symbol("Ziggy");
    const kanren = ast.Symbol("Kanren");

    states = undefined;
    states_slice = try RunGoal(states[0..0], 5, Disj(EqualO(ziggy, x), EqualO(kanren, ast.Def("x"))));
    try std.testing.expect(2 == states_slice.len);
}
