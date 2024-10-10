const std = @import("std");

pub const main = @import("main.zig").main;

test "all tests" {
    _ = @import("./http_one_dot_one_request_reader.zig");
    _ = @import("./str/string_delimiter_reader.zig");
}
