const std = @import("std");
const ast = @import("micro/ast.zig");
const goal = @import("micro/goal.zig");
const reify = @import("micro/reify.zig");
const state = @import("micro/state.zig");
const stream = @import("micro/stream.zig");
const globals = @import("micro/globals.zig");

// TODO:
// Implement with Closure type from closure.zig
const FivesClosure = struct {
    var expr: *const ast.Expr = undefined;

    pub fn func(state_: state.State) stream.StreamOptErrorUnion {
        return Fives(expr)(state_);
    }
};

// TODO:
// Implement with Closure type from closure.zig
const SixesClosure = struct {
    var expr: *const ast.Expr = undefined;

    pub fn func(state_: state.State) stream.StreamOptErrorUnion {
        return Sixes(expr)(state_);
    }
};

pub fn Fives(expr: *const ast.Expr) goal.Goal {
    FivesClosure.expr = expr;
    return stream.Zzz(goal.Disj(goal.EqualO(expr, ast.Int(5)), FivesClosure.func));
}

pub fn Sixes(expr: *const ast.Expr) goal.Goal {
    SixesClosure.expr = expr;
    return stream.Zzz(goal.Disj(goal.EqualO(expr, ast.Int(6)), SixesClosure.func));
}

// TODO:
// Implement with Closure type from closure.zig
const TestsClosure = struct {
    pub fn func1(expr: *const ast.Expr) goal.Goal {
        return goal.EqualO(expr, ast.Int(5));
    }

    pub fn func2(expr: *const ast.Expr) goal.Goal {
        FivesClosure.expr = expr;
        return FivesClosure.func;
    }

    pub fn func3(expr: *const ast.Expr) goal.Goal {
        FivesClosure.expr = expr;
        SixesClosure.expr = expr;
        return goal.Disj(FivesClosure.func, SixesClosure.func);
    }
};

test "Fives and Sixes" {
    const six = ast.Int(6);
    const five = ast.Int(5);

    var states: [globals.MAX_NUM_STATES]state.State = undefined;
    var states_slice = try goal.RunGoal(states[0..0], 1, goal.Fresh(TestsClosure.func1));
    var exprs: [globals.MAX_NUM_STATES]?*const ast.Expr = undefined;
    var actual = try reify.Reify(exprs[0..0], states_slice);
    const one_five = [_]?*const ast.Expr{five};
    try std.testing.expectEqual(one_five[0].?.*, actual[0].?.*);

    states = undefined;
    states_slice = try goal.RunGoal(states[0..0], 2, goal.Fresh(TestsClosure.func2));
    actual = try reify.Reify(exprs[0..0], states_slice);
    const two_fives = [_]?*const ast.Expr{ five, five };
    std.debug.print("\n{s}\n", .{two_fives});
    std.debug.print("\n{s}\n", .{actual});
    try std.testing.expectEqual(two_fives[0].?.*, actual[0].?.*);
    try std.testing.expectEqual(two_fives[1].?.*, actual[1].?.*);

    states = undefined;
    states_slice = try goal.RunGoal(states[0..0], 10, goal.Fresh(TestsClosure.func3));
    actual = try reify.Reify(exprs[0..0], states_slice);
    const ten_fives_and_sixes = [_]?*const ast.Expr{ five, six, five, six, five, six, five, six, five, six };
    try std.testing.expectEqual(ten_fives_and_sixes[0].?.*, actual[0].?.*);
    try std.testing.expectEqual(ten_fives_and_sixes[1].?.*, actual[1].?.*);
}
