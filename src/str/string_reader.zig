const std = @import("std");

pub const StringDelimiterReader = struct {
    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    pub fn readBufferIntoArrayListUntilDelimiter(_: *Self, comptime T: type, _: []const T, _: *std.ArrayList(T), delimiter: []const T) !void {
        if (delimiter.len == 0) return error.EmptyDelimiter;
    }
};

test "StringDelimiterReader returns an error if an empty delimiter is specified" {
    var string_delimiter_reader = StringDelimiterReader.init();

    const allocator = std.testing.allocator;

    var array_list = std.ArrayList(u8).init(allocator);

    const err = string_delimiter_reader.readBufferIntoArrayListUntilDelimiter(u8, "ABC", &array_list, "");

    try std.testing.expectEqual(error.EmptyDelimiter, err);
}
