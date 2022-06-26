const std = @import("std");

pub fn Closure(comptime func: anytype) type {
    const EnvType = @typeInfo(@TypeOf(func)).Fn.args[0].arg_type.?;
    const RetType = @typeInfo(@TypeOf(func)).Fn.return_type.?;
    return struct {
        const Self = @This();

        env: EnvType,

        pub fn init(env: EnvType) Self {
            return .{ .env = env };
        }

        pub fn call(self: Self, args: anytype) RetType {
            return @call(.{}, func, .{self.env} ++ args);
        }
    };
}

test "Closure" {
    const closure = Closure(struct {
        fn func(env: struct { number: usize }, increment: usize) usize {
            return env.number + increment;
        }
    }.func).init(.{ .number = 10 });
    try std.testing.expect(10 == closure.call(.{0}));
    try std.testing.expect(11 == closure.call(.{1}));
}
