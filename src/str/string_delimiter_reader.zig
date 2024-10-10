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
                    return self.current_match_index;
                }

                buffer_index += 1;
                self.read_char_count += 1;
            }

            return null;
        }

        pub fn deinit(_: *Self) void {}
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
