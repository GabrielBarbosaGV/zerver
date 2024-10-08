const std = @import("std");

pub const StringDelimiterReader = struct {
    const Self = @This();

    pub fn init(_: std.mem.Allocator) !Self {
        return Self{};
    }

    pub fn deinit(_: *Self) void {}

    pub fn readBufferIntoArrayListUntilDelimiter(self: *Self, comptime T: type, buffer: []const T, array_list: *std.ArrayList(T), delimiter: []const T) !void {
        if (delimiter.len == 0)
            return error.EmptyDelimiter;

        if (self.findDelimiterIndex(T, buffer, delimiter)) |i| {
            try array_list.appendSlice(buffer[0..i]);
        } else {
            try array_list.appendSlice(buffer);
        }
    }

    fn findDelimiterIndex(_: *Self, comptime T: type, buffer: []const T, delimiter: []const T) ?usize {
        var i: usize = 0;
        var delimiter_i: usize = 0;
        var match_start_index: ?usize = null;

        while (i < buffer.len and delimiter_i < delimiter.len) {
            if (buffer[i] == delimiter[delimiter_i]) {
                match_start_index = match_start_index orelse i;
                delimiter_i += 1;
            } else {
                delimiter_i = 0;
                match_start_index = null;
            }

            i += 1;
        }

        if (delimiter_i < delimiter.len) {
            match_start_index = null;
        }

        return match_start_index;
    }
};

test "StringDelimiterReader returns an error if an empty delimiter is specified" {
    const allocator = std.testing.allocator;

    var string_delimiter_reader = try StringDelimiterReader.init(allocator);
    defer string_delimiter_reader.deinit();

    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    const err = string_delimiter_reader.readBufferIntoArrayListUntilDelimiter(u8, "ABC", &array_list, "");

    try std.testing.expectEqual(error.EmptyDelimiter, err);
}

test "StringDelimiterReader writes a \"AB\" out of \"ABC\" with single-character delimiter \"C\"" {
    const allocator = std.testing.allocator;

    var string_delimiter_reader = try StringDelimiterReader.init(allocator);
    defer string_delimiter_reader.deinit();

    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try string_delimiter_reader.readBufferIntoArrayListUntilDelimiter(u8, "ABC", &array_list, "C");

    try std.testing.expectEqualStrings("AB", array_list.items);
}

test "StringDelimiterReader writes \"Test\" out of \"Test phrase\" with space delimiter" {
    const allocator = std.testing.allocator;

    var string_delimiter_reader = try StringDelimiterReader.init(allocator);
    defer string_delimiter_reader.deinit();

    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try string_delimiter_reader.readBufferIntoArrayListUntilDelimiter(u8, "Test phrase", &array_list, " ");

    try std.testing.expectEqualStrings("Test", array_list.items);
}

test "StringDelimiterReader does not write \"Test p\", but \"Test phrase\", out of \"Test phrase\" with \"hrae\" delimiter" {
    const allocator = std.testing.allocator;

    var string_delimiter_reader = try StringDelimiterReader.init(allocator);
    defer string_delimiter_reader.deinit();

    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try string_delimiter_reader.readBufferIntoArrayListUntilDelimiter(u8, "Test phrase", &array_list, "hrae");

    try std.testing.expectEqualStrings("Test phrase", array_list.items);
}

test "StringDelimiterReader writes whole buffer even if delimiter is longer than buffer" {
    const allocator = std.testing.allocator;

    var string_delimiter_reader = try StringDelimiterReader.init(allocator);
    defer string_delimiter_reader.deinit();

    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try string_delimiter_reader.readBufferIntoArrayListUntilDelimiter(u8, "T", &array_list, "Tea");

    try std.testing.expectEqualStrings("T", array_list.items);
}
