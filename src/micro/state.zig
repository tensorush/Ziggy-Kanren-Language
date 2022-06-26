const std = @import("std");
const ast = @import("ast.zig");
const goal = @import("goal.zig");
const reify = @import("reify.zig");
const stream = @import("stream.zig");
const globals = @import("globals.zig");

pub const State = struct {
    subs_opt: ?Substitutions = null,
    num_vars: usize = 0,

    pub fn isEqual(self: State, other: State) bool {
        return std.meta.eql(self, other);
    }

    pub fn format(self: State, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        if (self.subs_opt) |*subs| {
            try writer.writeAll("(");
            try subs.format(fmt, options, writer);
            try writer.print(" . {d})", .{self.num_vars});
        } else {
            try writer.print("(() . {d})", .{self.num_vars});
        }
    }
};

pub const Substitutions = struct {
    map: [globals.MAX_NUM_VARS]?*const ast.Expr = [_]?*const ast.Expr{null} ** globals.MAX_NUM_VARS,
    len: usize = 0,

    pub fn isEqual(self: Substitutions, other: Substitutions) bool {
        return std.meta.eql(self, other);
    }

    pub fn put(self: *Substitutions, index: usize, expr_opt: ?*const ast.Expr) void {
        self.map[index] = expr_opt;
        self.len += 1;
    }

    pub fn format(self: *const Substitutions, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        var exprs: [self.map.len]?*const ast.Expr = undefined;
        var cur_expr = exprs.len;
        for (self.map) |sub_opt, i| {
            const sub = sub_opt orelse continue;
            cur_expr -= 1;
            exprs[cur_expr] = ast.Cons(&globals.VARS[i], sub);
        }
        const list_string = std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{ast.List(exprs[cur_expr..])}) catch unreachable;
        try writer.print("{s}", .{list_string[1 .. list_string.len - 1]});
    }
};

pub fn Exts(atom_var: *const ast.Expr, expr_opt: ?*const ast.Expr, subs_opt: ?Substitutions) ?Substitutions {
    if (Occurs(atom_var, expr_opt, subs_opt)) return null;
    var ext_subs = if (subs_opt) |subs| subs else Substitutions{};
    ext_subs.put(atom_var.atom.variable.index, expr_opt);
    return ext_subs;
}

pub fn Occurs(atom_var: *const ast.Expr, expr_opt: ?*const ast.Expr, subs_opt: ?Substitutions) bool {
    const sub_expr_opt = if (ast.isVariable(expr_opt)) |atom_var2| Walk(atom_var2, subs_opt) else expr_opt;
    if (ast.isVariable(sub_expr_opt)) |sub_expr| {
        return sub_expr.isEqual(atom_var);
    } else if (ast.isPair(sub_expr_opt)) |sub_expr| {
        return Occurs(atom_var, ast.Car(sub_expr), subs_opt) or Occurs(atom_var, ast.Cdr(sub_expr), subs_opt);
    } else {
        return false;
    }
}

pub fn WalkStar(expr_opt: ?*const ast.Expr, subs_opt: ?Substitutions) ?*const ast.Expr {
    const sub_expr_opt = if (ast.isVariable(expr_opt)) |atom_var| Walk(atom_var, subs_opt) else expr_opt;
    if (ast.isVariable(sub_expr_opt)) |sub_expr| {
        return sub_expr;
    } else if (ast.isPair(sub_expr_opt)) |sub_expr| {
        return ast.Cons(WalkStar(ast.Car(sub_expr), subs_opt), WalkStar(ast.Cdr(sub_expr), subs_opt));
    } else {
        return sub_expr_opt;
    }
}

pub fn Walk(atom_var: *const ast.Expr, subs_opt: ?Substitutions) *const ast.Expr {
    const expr_opt = if (subs_opt) |subs| subs.map[atom_var.atom.variable.index] else null;
    if (expr_opt) |expr| {
        return if (ast.isVariable(expr)) |_| Walk(expr, subs_opt) else expr;
    } else {
        return atom_var;
    }
}

test "Walk" {
    const v = ast.Def("v");
    const w = ast.Def("w");
    const x = ast.Def("x");
    const y = ast.Def("y");
    const z = ast.Def("z");

    var subs = Substitutions{};
    subs.put(z.atom.variable.index, ast.Symbol("a"));
    subs.put(x.atom.variable.index, w);
    subs.put(y.atom.variable.index, z);
    try std.testing.expectEqualStrings("a", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{Walk(z, subs)}));
    try std.testing.expectEqualStrings("a", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{Walk(y, subs)}));
    try std.testing.expectEqualStrings(",w", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{Walk(x, subs)}));

    subs = Substitutions{};
    subs.put(x.atom.variable.index, y);
    subs.put(v.atom.variable.index, x);
    subs.put(w.atom.variable.index, x);
    try std.testing.expectEqualStrings(",y", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{Walk(x, subs)}));
    try std.testing.expectEqualStrings(",y", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{Walk(v, subs)}));
    try std.testing.expectEqualStrings(",y", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{Walk(w, subs)}));

    subs = Substitutions{};
    subs.put(x.atom.variable.index, ast.Symbol("e"));
    subs.put(z.atom.variable.index, x);
    subs.put(y.atom.variable.index, z);
    try std.testing.expectEqualStrings("e", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{Walk(y, subs)}));

    subs = Substitutions{};
    var exprs = [_]?*const ast.Expr{ x, ast.Symbol("e"), z };
    subs.put(x.atom.variable.index, ast.Symbol("b"));
    subs.put(z.atom.variable.index, y);
    subs.put(w.atom.variable.index, ast.List(exprs[0..]));
    try std.testing.expectEqualStrings("(,x e ,z)", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{Walk(w, subs)}));
}

test "WalkStar" {
    const v = ast.Def("v");
    const w = ast.Def("w");
    const x = ast.Def("x");
    const y = ast.Def("y");
    const z = ast.Def("z");

    var subs = Substitutions{};
    subs.put(z.atom.variable.index, ast.Symbol("a"));
    subs.put(x.atom.variable.index, w);
    subs.put(y.atom.variable.index, z);
    try std.testing.expectEqualStrings("a", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{WalkStar(z, subs)}));
    try std.testing.expectEqualStrings("a", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{WalkStar(y, subs)}));
    try std.testing.expectEqualStrings(",w", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{WalkStar(x, subs)}));

    subs = Substitutions{};
    subs.put(x.atom.variable.index, y);
    subs.put(v.atom.variable.index, x);
    subs.put(w.atom.variable.index, x);
    try std.testing.expectEqualStrings(",y", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{WalkStar(x, subs)}));
    try std.testing.expectEqualStrings(",y", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{WalkStar(v, subs)}));
    try std.testing.expectEqualStrings(",y", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{WalkStar(w, subs)}));

    subs = Substitutions{};
    var exprs = [_]?*const ast.Expr{ x, ast.Symbol("e"), z };
    subs.put(x.atom.variable.index, ast.Symbol("b"));
    subs.put(z.atom.variable.index, y);
    subs.put(w.atom.variable.index, ast.List(exprs[0..]));
    try std.testing.expectEqualStrings("(b e ,y)", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{WalkStar(w, subs)}));

    subs = Substitutions{};
    subs.put(x.atom.variable.index, ast.Symbol("e"));
    subs.put(z.atom.variable.index, x);
    subs.put(y.atom.variable.index, z);
    try std.testing.expectEqualStrings("e", try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{WalkStar(y, subs)}));
}

test "Occurs" {
    const x = ast.Def("x");
    const y = ast.Def("y");

    var actual = Occurs(x, x, Substitutions{});
    try std.testing.expectEqual(true, actual);

    actual = Occurs(x, y, null);
    try std.testing.expectEqual(false, actual);

    var exprs = [_]?*const ast.Expr{y};
    var subs = Substitutions{};
    subs.put(y.atom.variable.index, x);
    actual = Occurs(x, ast.List(exprs[0..]), subs);
    try std.testing.expectEqual(true, actual);
}

test "Exts" {
    const x = ast.Def("x");
    const y = ast.Def("y");
    const z = ast.Def("z");
    const ziggy = ast.Symbol("Ziggy");

    var subs = Substitutions{};
    var actual = Exts(x, ziggy, subs);
    subs.put(x.atom.variable.index, ziggy);
    var expected: ?Substitutions = subs;
    try std.testing.expectEqual(expected, actual);

    var exprs = [_]?*const ast.Expr{x};
    actual = Exts(x, ast.List(exprs[0..]), null);
    expected = null;
    try std.testing.expectEqual(expected, actual);

    exprs = .{y};
    subs = Substitutions{};
    subs.put(y.atom.variable.index, x);
    actual = Exts(x, ast.List(exprs[0..]), subs);
    expected = null;
    try std.testing.expectEqual(expected, actual);

    subs = Substitutions{};
    subs.put(z.atom.variable.index, x);
    subs.put(y.atom.variable.index, z);
    expected = subs;
    actual = Exts(x, ziggy, expected);
    expected.?.put(x.atom.variable.index, ziggy);
    try std.testing.expectEqual(expected, actual);
}
