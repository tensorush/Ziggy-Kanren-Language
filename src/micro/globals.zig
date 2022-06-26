const ast = @import("ast.zig");
const stream = @import("stream.zig");

pub var CUR_NUM_VARS: usize = 0;
pub var CUR_NUM_PAIRS: usize = 0;
pub var CUR_NUM_STATES: usize = 0;
pub var CUR_NUM_NON_VARS: usize = 0;

pub const MAX_BUF_LEN: usize = 1 << 7;
pub const MAX_NUM_VARS: usize = 1 << 7;
pub const MAX_NUM_PAIRS: usize = 1 << 7;
pub const MAX_NUM_STATES: usize = 1 << 7;
pub const MAX_NUM_NON_VARS: usize = 1 << 7;

pub var VARS: [MAX_NUM_VARS]ast.Expr = undefined;
pub var PAIRS: [MAX_NUM_PAIRS]ast.Expr = undefined;
pub var NON_VARS: [MAX_NUM_NON_VARS]ast.Expr = undefined;
pub var STREAMS: [MAX_NUM_STATES]stream.Stream = undefined;
