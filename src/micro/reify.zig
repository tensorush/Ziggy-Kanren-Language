const std = @import("std");
const ast = @import("ast.zig");
const goal = @import("goal.zig");
const state = @import("state.zig");
const globals = @import("globals.zig");

pub fn Reify(exprs_slice: []?*const ast.Expr, states_slice: []state.State) std.fmt.AllocPrintError![]?*const ast.Expr {
    var new_exprs_slice = exprs_slice;
    for (states_slice) |state_, i| {
        new_exprs_slice.len += 1;
        new_exprs_slice[i] = try ReifyIndex(0, state_);
    }
    return new_exprs_slice;
}

pub fn ReifyName(name: []const u8, state_: state.State) std.fmt.AllocPrintError!?*const ast.Expr {
    const atom_var = ast.Expr{ .atom = .{ .variable = .{ .name = name } } };
    const expr = state.WalkStar(atom_var, state_.subs_opt);
    const subs = try ReifySubs(expr, null);
    return state.WalkStar(expr, subs);
}

pub fn ReifyIndex(index: usize, state_: state.State) std.fmt.AllocPrintError!?*const ast.Expr {
    const atom_var = ast.Expr{ .atom = .{ .variable = .{ .index = index } } };
    const expr = state.WalkStar(&atom_var, state_.subs_opt);
    const subs = try ReifySubs(expr, null);
    return state.WalkStar(expr, subs);
}

pub fn ReifySubs(expr_opt: ?*const ast.Expr, subs_opt: ?state.Substitutions) std.fmt.AllocPrintError!state.Substitutions {
    const sub_expr_opt = if (ast.isVariable(expr_opt)) |atom_var| state.Walk(atom_var, subs_opt) else expr_opt;
    if (ast.isVariable(sub_expr_opt)) |sub_expr| {
        var reified_subs = subs_opt orelse state.Substitutions{};
        const symbol = ast.Symbol(try std.fmt.allocPrint(std.heap.page_allocator, "_{d}", .{reified_subs.len}));
        reified_subs.put(sub_expr.atom.variable.index, symbol);
        return reified_subs;
    } else if (ast.isPair(sub_expr_opt)) |sub_expr| {
        return try ReifySubs(ast.Cdr(sub_expr), try ReifySubs(ast.Car(sub_expr), subs_opt));
    } else {
        return subs_opt orelse state.Substitutions{};
    }
}

test "ReifyIndex" {
    const u = ast.Def("u");
    const v = ast.Def("v");
    const w = ast.Def("w");
    const x = ast.Def("x");
    const y = ast.Def("y");
    const z = ast.Def("z");

    var wvu = [_]?*const ast.Expr{ w, v, u };
    var ice = [_]?*const ast.Expr{ast.Symbol("ice")};
    var ice_z = [_]?*const ast.Expr{ ast.List(ice[0..]), z };
    var xuwyz_ice_z = [_]?*const ast.Expr{ x, u, w, y, z, ast.List(ice_z[0..]) };
    var exprs = [_]?*const ast.Expr{ ast.List(xuwyz_ice_z[0..]), ast.Cons(y, ast.Symbol("fire")), ast.List(wvu[0..]) };
    const expr = ast.List(exprs[0..]).?;
    var subs = state.Substitutions{};
    subs.put(x.atom.variable.index, ast.Cdr(ast.Car(expr)));
    subs.put(y.atom.variable.index, ast.Cdr(ast.Car(ast.Cdr(expr))));
    subs.put(w.atom.variable.index, ast.Cdr(ast.Car(ast.Cdr(ast.Cdr(expr)))));
    var actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{try ReifyIndex(x.atom.variable.index, .{ .subs_opt = subs })});
    try std.testing.expectEqualStrings("(_0 (_1 _0) fire _2 ((ice) _2))", actual);

    // const g = goal.Disj(goal.EqualO(ast.Symbol("Ziggy"), x), goal.EqualO(ast.Symbol("Kanren"), x));
    // var states: [globals.MAX_NUM_STATES]state.State = undefined;
    // var states_slice = try goal.RunGoal(states[0..0], 5, g);
    // actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{try ReifyIndex(x.atom.variable.index, states_slice[0])});
    // try std.testing.expectEqualStrings("Ziggy", actual);
    // actual = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{try ReifyIndex(x.atom.variable.index, states_slice[1])});
    // try std.testing.expectEqualStrings("Kanren", actual);
}
