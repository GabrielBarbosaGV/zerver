const std = @import("std");
const DelimiterReader = @import("./str/delimiter_reader.zig").DelimiterReader;

pub const HttpOneDotOneRequestReader = struct {
    request_info: RequestInfo,
    allocator: std.mem.Allocator,
    previous_bytes: std.ArrayList(u8),
    cursor_position: usize,
    strings_to_request_types: std.StringHashMap(RequestType),
    read_state: ReadState,
    should_continue_reading: bool,
    carriage_return_newline_delimiter_reader: DelimiterReader(u8),
    space_delimiter_reader: DelimiterReader(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const request_info = RequestInfo.init(allocator);

        const previous_bytes = std.ArrayList(u8).init(allocator);

        var strings_to_request_types = std.StringHashMap(RequestType).init(allocator);

        try insertStringRequestTypes(&strings_to_request_types);

        var carriage_return_newline_delimiter_reader = try DelimiterReader(u8).init("\r\n", allocator);
        var space_delimiter_reader = try DelimiterReader(u8).init(" ", allocator);

        carriage_return_newline_delimiter_reader.number_to_return = .return_end_of_match_over_this_line;
        space_delimiter_reader.number_to_return = .return_end_of_match_over_this_line;

        return Self{
            .allocator = allocator,
            .request_info = request_info,
            .previous_bytes = previous_bytes,
            .strings_to_request_types = strings_to_request_types,
            .cursor_position = 0,
            .read_state = .http_method,
            .should_continue_reading = true,
            .carriage_return_newline_delimiter_reader = carriage_return_newline_delimiter_reader,
            .space_delimiter_reader = space_delimiter_reader,
        };
    }

    pub fn deinit(self: *Self) void {
        self.request_info.deinit();
        self.strings_to_request_types.deinit();
        self.previous_bytes.deinit();
        self.carriage_return_newline_delimiter_reader.deinit();
        self.space_delimiter_reader.deinit();
    }

    pub fn readNextBytes(self: *Self, next_bytes: []const u8) !void {
        self.cursor_position = 0;

        self.setShouldContinueReading(true);

        while (self.shouldContinueReading()) {
            switch (self.read_state) {
                .http_method => try self.readHttpMethod(next_bytes),

                .route => try self.readRoute(next_bytes),

                .protocol_version => try self.readProtocolVersion(next_bytes),

                .end => self.setShouldContinueReading(false),
            }
        }
    }

    fn readHttpMethod(self: *Self, next_bytes: []const u8) !void {
        const has_read_whole_http_method = try self.readUptoDelimiter(next_bytes, &self.space_delimiter_reader);

        if (!has_read_whole_http_method) {
            self.setShouldContinueReading(false);
            return;
        }

        self.space_delimiter_reader.reset();

        if (self.strings_to_request_types.get(self.previous_bytes.items)) |request_type| {
            self.request_info.request_type = request_type;
        } else {
            return RequestReadError.UnknownHttpMethod;
        }

        self.setReadingRoute();
        self.clearPreviousBytes();
    }

    pub fn writePreviousBytesInto(self: *Self, array_list: *std.ArrayList(u8)) !void {
        try array_list.appendSlice(self.previous_bytes.items);
    }

    fn readRoute(self: *Self, next_bytes: []const u8) !void {
        const has_read_whole_route = try self.readUptoDelimiter(next_bytes, &self.space_delimiter_reader);

        if (!has_read_whole_route) {
            self.setShouldContinueReading(false);
            return;
        }

        try self.request_info.route.appendSlice(self.previous_bytes.items);

        self.setReadingProtocolVersion();
        self.clearPreviousBytes();
    }

    fn readProtocolVersion(self: *Self, next_bytes: []const u8) !void {
        var has_read_whole_protocol_version = false;

        for (next_bytes[self.cursor_position..]) |byte| {
            if (byte == '\n') {
                has_read_whole_protocol_version = true;
                break;
            }

            self.cursor_position += 1;
            try self.previous_bytes.append(byte);
        }

        if (!has_read_whole_protocol_version) {
            self.setShouldContinueReading(false);
            return;
        }

        if (!std.mem.eql(u8, "HTTP/1.1", self.previous_bytes.items))
            return RequestReadError.NotOneDotOne;

        self.clearPreviousBytes();
        self.cursor_position += 1;
    }

    fn readUntilDelimiterChar(self: *Self, next_bytes: []const u8, delimiter: u8) !bool {
        var has_read_upto_delimiter = false;

        for (next_bytes[self.cursor_position..]) |byte| {
            if (byte == delimiter) {
                has_read_upto_delimiter = true;
                break;
            }

            self.cursor_position += 1;
            try self.previous_bytes.append(byte);
        }

        return has_read_upto_delimiter;
    }

    fn readUptoDelimiter(self: *Self, next_bytes: []const u8, delimiter_reader: *DelimiterReader(u8)) !bool {
        const index: ?usize = delimiter_reader.readNextItems(next_bytes[self.cursor_position..]);

        if (index) |i| {
            try self.previous_bytes.appendSlice(next_bytes[self.cursor_position..(self.cursor_position + i - 1)]);

            self.cursor_position += i;

            return true;
        } else {
            self.cursor_position += next_bytes.len;

            try self.previous_bytes.appendSlice(next_bytes);

            return false;
        }
    }

    fn calculateIndexOfEndOfMatch(self: *Self, match_index: usize) usize {
        return match_index - self.previous_bytes.items.len;
    }

    pub fn clearPreviousBytes(self: *Self) void {
        self.previous_bytes.deinit();

        self.previous_bytes = std.ArrayList(u8).init(self.allocator);
    }

    pub fn setReadingRoute(self: *Self) void {
        self.read_state = .route;
    }

    pub fn setReadingHttpMethod(self: *Self) void {
        self.read_state = .http_method;
    }

    pub fn setReadingProtocolVersion(self: *Self) void {
        self.read_state = .protocol_version;
    }

    pub fn setReachedEnd(self: *Self) void {
        self.read_state = .end;
    }

    fn resetCursorPosition(self: *Self) void {
        self.cursor_position = 0;
    }

    fn shouldContinueReading(self: *Self) bool {
        return self.should_continue_reading;
    }

    pub fn setShouldContinueReading(self: *Self, should_continue_reading: bool) void {
        self.should_continue_reading = should_continue_reading;
    }
};

const RequestInfo = struct {
    request_type: ?RequestType,
    route: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) RequestInfo {
        return Self{
            .request_type = null,
            .route = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.route.deinit();
    }
};

const RequestType = enum {
    get,
    post,
    head,
    put,
    delete,
    connect,
    options,
    trace,
    patch,
};

const ReadState = enum {
    http_method,
    route,
    protocol_version,
    end,
};

const RequestReadError = error{ UnknownHttpMethod, UnsupportedProtocol, NotOneDotOne };

const METHOD_NAMES_TO_REQUEST_TYPES = [_]HttpMethodTuple{
    .{ "GET", .get },
    .{ "POST", .post },
    .{ "HEAD", .head },
    .{ "PUT", .put },
    .{ "DELETE", .delete },
    .{ "CONNECT", .connect },
    .{ "OPTIONS", .options },
    .{ "TRACE", .trace },
    .{ "PATCH", .patch },
};

fn insertStringRequestTypes(hash_map: *std.StringHashMap(RequestType)) !void {
    for (METHOD_NAMES_TO_REQUEST_TYPES) |tuple| {
        try hash_map.put(tuple[0], tuple[1]);
    }
}

test "HttpOneDotOneRequestReader reports reading a GET request for the \"GET\" string" {
    const request: []const u8 = "GET ";

    const allocator = std.testing.allocator;

    var http_one_dot_one_request_reader = try HttpOneDotOneRequestReader.init(allocator);
    defer http_one_dot_one_request_reader.deinit();

    try http_one_dot_one_request_reader.readNextBytes(request);

    const request_info = http_one_dot_one_request_reader.request_info;

    try std.testing.expectEqual(.get, request_info.request_type);
}

test "HttpOneDotOneRequestReader reports reading a GET request when it is split into multiple strings" {
    const request_first_part: []const u8 = "GE";
    const request_second_part: []const u8 = "T ";

    const allocator = std.testing.allocator;

    var http_one_dot_one_request_reader = try HttpOneDotOneRequestReader.init(allocator);
    defer http_one_dot_one_request_reader.deinit();

    try http_one_dot_one_request_reader.readNextBytes(request_first_part);
    try http_one_dot_one_request_reader.readNextBytes(request_second_part);

    const request_info = http_one_dot_one_request_reader.request_info;

    try std.testing.expectEqual(.get, request_info.request_type);
}

const HttpMethodTuple = std.meta.Tuple(&.{ []const u8, RequestType });

test "HttpOneDotOneRequestReader knows all HTTP methods" {
    for (METHOD_NAMES_TO_REQUEST_TYPES) |tuple| {
        try assertVerbIsKnown(tuple);
    }
}

fn assertVerbIsKnown(tuple: HttpMethodTuple) !void {
    const method_name = tuple[0];

    const allocator = std.testing.allocator;

    var request_list = std.ArrayList(u8).init(allocator);
    defer request_list.deinit();

    try request_list.appendSlice(method_name);
    try request_list.append(' ');

    const request = request_list.items;

    var http_one_dot_one_request_reader = try HttpOneDotOneRequestReader.init(allocator);
    defer http_one_dot_one_request_reader.deinit();

    try http_one_dot_one_request_reader.readNextBytes(request);

    const request_info = http_one_dot_one_request_reader.request_info;

    try std.testing.expectEqual(tuple[1], request_info.request_type);
}

test "HttpOneDotOneRequestReader reports unknown HTTP method" {
    const request: []const u8 = "SPLASH ";

    const allocator = std.testing.allocator;

    var http_one_dot_one_request_reader = try HttpOneDotOneRequestReader.init(allocator);
    defer http_one_dot_one_request_reader.deinit();

    http_one_dot_one_request_reader.setReadingHttpMethod();

    const err = http_one_dot_one_request_reader.readNextBytes(request);

    try std.testing.expectEqual(RequestReadError.UnknownHttpMethod, err);
}

test "HttpOneDotOneRequestReader returns unknown HTTP method string" {
    const request: []const u8 = "SPLASH ";

    const allocator = std.testing.allocator;

    var http_one_dot_one_request_reader = try HttpOneDotOneRequestReader.init(allocator);
    defer http_one_dot_one_request_reader.deinit();

    http_one_dot_one_request_reader.setReadingHttpMethod();

    const err = http_one_dot_one_request_reader.readNextBytes(request);

    var unknown_http_method = std.ArrayList(u8).init(allocator);
    defer unknown_http_method.deinit();

    try http_one_dot_one_request_reader.writePreviousBytesInto(&unknown_http_method);

    try std.testing.expectEqualStrings("SPLASH", unknown_http_method.items);
    try std.testing.expectEqual(RequestReadError.UnknownHttpMethod, err);
}

test "HttpOneDotOneRequestReader reports correct route" {
    const request: []const u8 = "/a/b/c ";

    const allocator = std.testing.allocator;

    var http_one_dot_one_request_reader = try HttpOneDotOneRequestReader.init(allocator);
    defer http_one_dot_one_request_reader.deinit();

    http_one_dot_one_request_reader.setReadingRoute();

    try http_one_dot_one_request_reader.readNextBytes(request);

    try std.testing.expectEqualStrings("/a/b/c", http_one_dot_one_request_reader.request_info.route.items);
}

test "HttpOneDotOneRequestReader reports correct route after reading both request type and route" {
    const request: []const u8 = "GET /a/b/c ";

    const allocator = std.testing.allocator;

    var http_one_dot_one_request_reader = try HttpOneDotOneRequestReader.init(allocator);
    defer http_one_dot_one_request_reader.deinit();

    try http_one_dot_one_request_reader.readNextBytes(request);

    try std.testing.expectEqual(.get, http_one_dot_one_request_reader.request_info.request_type);

    try std.testing.expectEqualStrings("/a/b/c", http_one_dot_one_request_reader.request_info.route.items);
}

test "HttpOneDotOneRequestReader reports reading correct route when it is split" {
    const first_request: []const u8 = "/a/";
    const second_request: []const u8 = "b/c ";

    const allocator = std.testing.allocator;

    var http_one_dot_one_request_reader = try HttpOneDotOneRequestReader.init(allocator);
    defer http_one_dot_one_request_reader.deinit();

    http_one_dot_one_request_reader.setReadingRoute();

    try http_one_dot_one_request_reader.readNextBytes(first_request);
    try http_one_dot_one_request_reader.readNextBytes(second_request);

    try std.testing.expectEqualStrings("/a/b/c", http_one_dot_one_request_reader.request_info.route.items);
}
