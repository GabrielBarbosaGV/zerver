const std = @import("std");

pub fn DelimiterReader(comptime T: type) type {
    return struct {
        delimiter: []const T,
        delimiter_index: usize,
        current_match_index: ?usize,
        read_char_count: usize,

        const Self = @This();

        pub fn init(delimiter: []const T, _: std.mem.Allocator) !Self {
            return Self{
                .delimiter = delimiter,
                .delimiter_index = 0,
                .current_match_index = null,
                .read_char_count = 0,
            };
        }

        pub fn readNextItems(self: *Self, buffer: []const T) ?usize {
            var buffer_index: usize = 0;

            while (buffer_index < buffer.len) {
                if (buffer[buffer_index] == self.delimiter[self.delimiter_index]) {
                    self.delimiter_index += 1;
                    self.current_match_index = self.current_match_index orelse self.read_char_count;
                } else {
                    self.current_match_index = null;
                    self.delimiter_index = 0;
                }

                if (self.delimiter_index == self.delimiter.len) {
                    const i = self.current_match_index;

                    self.resetMatchAndDelimiterIndex();

                    self.read_char_count += self.delimiter.len - 1;

                    return i;
                } else {
                    self.read_char_count += 1;
                }

                buffer_index += 1;
            }

            return null;
        }

        pub fn deinit(_: *Self) void {}

        fn resetMatchAndDelimiterIndex(self: *Self) void {
            self.delimiter_index = 0;
            self.current_match_index = null;
        }

        pub fn reset(self: *Self) void {
            self.resetMatchAndDelimiterIndex();
            self.read_char_count = 0;
        }

        pub fn getDelimiter(self: *Self) *[]const u8 {
            return &self.delimiter;
        }
    };
}

test "DelimiterReader returns null on .getMatchIndex() if full delimiter was not yet found" {
    const allocator = std.testing.allocator;

    var delimiter_reader = try DelimiterReader(u8).init("C", allocator);
    defer delimiter_reader.deinit();

    const result = delimiter_reader.readNextItems("");

    try std.testing.expectEqual(null, result);
}

test "DelimiterReader returns 2 when attempting to get \"C\" from \"ABC\"" {
    const allocator = std.testing.allocator;

    var delimiter_reader = try DelimiterReader(u8).init("C", allocator);
    defer delimiter_reader.deinit();

    const result = delimiter_reader.readNextItems("ABC");

    try std.testing.expectEqual(2, result);
}

test "DelimiterReader returns 7 when attempting to get \"Fro\" from \"To and Fro\"" {
    const allocator = std.testing.allocator;

    var delimiter_reader = try DelimiterReader(u8).init("Fro", allocator);
    defer delimiter_reader.deinit();

    const result = delimiter_reader.readNextItems("To and Fro");

    try std.testing.expectEqual(7, result);
}

test "DelimiterReader returns 7 when attempting to get \"Fro\" from \"To and Fro\" over two lines" {
    const allocator = std.testing.allocator;

    var delimiter_reader = try DelimiterReader(u8).init("Fro", allocator);
    defer delimiter_reader.deinit();

    var result = delimiter_reader.readNextItems("To and");
    try std.testing.expectEqual(null, result);

    result = delimiter_reader.readNextItems(" Fro");
    try std.testing.expectEqual(7, result);
}

test "DelimiterReader returns 10 when attempting to get \"he\" from \"Here and there\" over three lines" {
    const allocator = std.testing.allocator;

    var delimiter_reader = try DelimiterReader(u8).init("he", allocator);
    defer delimiter_reader.deinit();

    var result = delimiter_reader.readNextItems("He");
    try std.testing.expectEqual(null, result);

    result = delimiter_reader.readNextItems("re");
    try std.testing.expectEqual(null, result);

    result = delimiter_reader.readNextItems(" and There");
    try std.testing.expectEqual(10, result);
}

test "DelimiterReader returns indices of matches on separate lines" {
    const allocator = std.testing.allocator;

    var delimiter_reader = try DelimiterReader(u8).init("he", allocator);
    defer delimiter_reader.deinit();

    var result = delimiter_reader.readNextItems("he");
    try std.testing.expectEqual(0, result);

    result = delimiter_reader.readNextItems("he");
    try std.testing.expectEqual(2, result);
}
