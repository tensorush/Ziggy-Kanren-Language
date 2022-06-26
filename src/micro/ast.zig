const std = @import("std");
const globals = @import("globals.zig");

pub const Expr = union(enum) {
    pair: Pair,
    atom: Atom,

    pub fn isEqual(self: *const Expr, other: *const Expr) bool {
        return std.meta.eql(self.*, other.*);
    }

    pub fn format(self_opt: ?Expr, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        if (self_opt) |self| {
            switch (self) {
                .pair => {
                    try writer.writeAll("(");
                    try self.pair.format(fmt, options, writer);
                    try writer.writeAll(")");
                },
                .atom => try self.atom.format(fmt, options, writer),
            }
        } else {
            try writer.writeAll("()");
        }
    }
};

pub const Pair = struct {
    car_opt: ?*const Expr,
    cdr_opt: ?*const Expr,

    pub fn format(self_opt: ?Pair, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        if (self_opt) |self| {
            if (self.car_opt) |car| {
                try car.format(fmt, options, writer);
            } else {
                try writer.writeAll("()");
            }
            if (self.cdr_opt) |cdr| {
                switch (cdr.*) {
                    .pair => {
                        try writer.writeAll(" ");
                        try cdr.pair.format(fmt, options, writer);
                    },
                    .atom => {
                        try writer.writeAll(" . ");
                        try cdr.atom.format(fmt, options, writer);
                    },
                }
            }
        } else {
            try writer.writeAll("");
        }
    }
};

pub const Atom = union(enum) {
    const Variable = struct {
        name: []const u8 = undefined,
        index: usize = undefined,
    };
    variable: Variable,
    symbol: []const u8,
    integer: i64,
    float: f64,

    pub fn format(self: Atom, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        switch (self) {
            .variable => try writer.print(",{s}", .{self.variable.name}),
            .symbol => try writer.print("{s}", .{self.symbol}),
            .integer => try writer.print("{d}", .{self.integer}),
            .float => try writer.print("{d}", .{self.float}),
        }
    }
};

pub fn isPair(expr_opt: ?*const Expr) ?*const Expr {
    if (expr_opt) |self| {
        return switch (self.*) {
            .pair => self,
            .atom => null,
        };
    } else {
        return null;
    }
}

pub fn isVariable(expr_opt: ?*const Expr) ?*const Expr {
    if (expr_opt) |self| {
        return switch (self.*) {
            .pair => null,
            .atom => switch (self.atom) {
                .variable => self,
                else => null,
            },
        };
    } else {
        return null;
    }
}

pub fn Def(name: []const u8) *const Expr {
    globals.VARS[globals.CUR_NUM_VARS] = .{ .atom = .{ .variable = .{ .name = name, .index = globals.CUR_NUM_VARS } } };
    defer globals.CUR_NUM_VARS += 1;
    return &globals.VARS[globals.CUR_NUM_VARS];
}

pub fn Symbol(symbol: []const u8) *const Expr {
    globals.NON_VARS[globals.CUR_NUM_NON_VARS] = .{ .atom = .{ .symbol = symbol } };
    defer globals.CUR_NUM_NON_VARS += 1;
    return &globals.NON_VARS[globals.CUR_NUM_NON_VARS];
}

pub fn Float(float: f64) *const Expr {
    globals.NON_VARS[globals.CUR_NUM_NON_VARS] = .{ .atom = .{ .float = float } };
    defer globals.CUR_NUM_NON_VARS += 1;
    return &globals.NON_VARS[globals.CUR_NUM_NON_VARS];
}

pub fn Int(integer: i64) *const Expr {
    globals.NON_VARS[globals.CUR_NUM_NON_VARS] = .{ .atom = .{ .integer = integer } };
    defer globals.CUR_NUM_NON_VARS += 1;
    return &globals.NON_VARS[globals.CUR_NUM_NON_VARS];
}

pub fn Quo(expr_opt: ?*const Expr) std.fmt.AllocPrintError![]const u8 {
    return try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{expr_opt});
}

pub fn Cons(car_opt: ?*const Expr, cdr_opt: ?*const Expr) *const Expr {
    globals.PAIRS[globals.CUR_NUM_PAIRS] = .{ .pair = .{ .car_opt = car_opt, .cdr_opt = cdr_opt } };
    defer globals.CUR_NUM_PAIRS += 1;
    return &globals.PAIRS[globals.CUR_NUM_PAIRS];
}

pub fn Car(expr_opt: ?*const Expr) ?*const Expr {
    if (expr_opt) |expr| {
        return switch (expr.*) {
            .pair => expr.pair.car_opt,
            .atom => unreachable,
        };
    } else {
        return null;
    }
}

pub fn Cdr(expr_opt: ?*const Expr) ?*const Expr {
    if (expr_opt) |expr| {
        return switch (expr.*) {
            .pair => expr.pair.cdr_opt,
            .atom => unreachable,
        };
    } else {
        return null;
    }
}

pub fn List(exprs_opt_slice: []?*const Expr) ?*const Expr {
    return switch (exprs_opt_slice.len) {
        0 => null,
        1 => Cons(exprs_opt_slice[0], null),
        else => Cons(exprs_opt_slice[0], List(exprs_opt_slice[1..])),
    };
}

test "Car" {
    try std.testing.expectEqualStrings(",a", try Quo(Car(Cons(Def("a"), Def("b")))));
    try std.testing.expectEqualStrings("(,a)", try Quo(Car(Cons(Cons(Def("a"), null), Def("b")))));
    try std.testing.expectEqualStrings("((,a))", try Quo(Car(Cons(Cons(Cons(Def("a"), null), null), Def("b")))));
    try std.testing.expectEqualStrings("(,a ,b)", try Quo(Car(Cons(Cons(Def("a"), Cons(Def("b"), null)), Def("c")))));
    try std.testing.expectEqualStrings("((,a ,b))", try Quo(Car(Cons(Cons(Cons(Def("a"), Cons(Def("b"), null)), null), Def("c")))));
}

test "Cdr" {
    try std.testing.expectEqualStrings(",b", try Quo(Cdr(Cons(Def("a"), Def("b")))));
    try std.testing.expectEqualStrings("(,b)", try Quo(Cdr(Cons(Def("a"), Cons(Def("b"), null)))));
    try std.testing.expectEqualStrings("((,b))", try Quo(Cdr(Cons(Def("a"), Cons(Cons(Def("b"), null), null)))));
    try std.testing.expectEqualStrings("(,b ,c)", try Quo(Cdr(Cons(Def("a"), Cons(Def("b"), Cons(Def("c"), null))))));
    try std.testing.expectEqualStrings("((,b ,c))", try Quo(Cdr(Cons(Def("a"), Cons(Cons(Def("b"), Cons(Def("c"), null)), null)))));
}
