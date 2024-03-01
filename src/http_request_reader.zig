const std = @import("std");

pub const HttpRequestReader = struct {
    request_info: RequestInfo,
    allocator: std.mem.Allocator,
    previous_bytes: std.ArrayList(u8),
    cursor_position: usize,
    strings_to_request_types: std.StringHashMap(RequestType),
    read_state: ReadState,
    should_continue_reading: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const request_info = RequestInfo.init(allocator);

        const previous_bytes = std.ArrayList(u8).init(allocator);

        var strings_to_request_types = std.StringHashMap(RequestType).init(allocator);

        try insertStringRequestTypes(&strings_to_request_types);

        return Self{
            .allocator = allocator,
            .request_info = request_info,
            .previous_bytes = previous_bytes,
            .strings_to_request_types = strings_to_request_types,
            .cursor_position = 0,
            .read_state = .http_method,
            .should_continue_reading = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.request_info.deinit();
        self.strings_to_request_types.deinit();
        self.previous_bytes.deinit();
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
        var has_read_whole_http_method = false;

        for (next_bytes) |byte| {
            if (byte == ' ') {
                has_read_whole_http_method = true;
                break;
            }

            self.cursor_position += 1;

            try self.previous_bytes.append(byte);
        }

        if (!has_read_whole_http_method) {
            self.setShouldContinueReading(false);
            return;
        }

        if (self.strings_to_request_types.get(self.previous_bytes.items)) |request_type| {
            self.request_info.request_type = request_type;
        }

        self.cursor_position += 1;
        self.setHasJustReadHttpMethod();
        self.clearPreviousBytes();
    }

    fn readRoute(self: *Self, next_bytes: []const u8) !void {
        if (next_bytes.len <= self.cursor_position) {
            self.setShouldContinueReading(false);
            return;
        }

        var has_read_whole_route = false;

        for (next_bytes[self.cursor_position..]) |byte| {
            if (byte == ' ') {
                has_read_whole_route = true;
                break;
            }

            self.cursor_position += 1;

            try self.previous_bytes.append(byte);
        }

        if (!has_read_whole_route) {
            self.setShouldContinueReading(false);
            return;
        }

        try self.request_info.route.appendSlice(self.previous_bytes.items);

        self.cursor_position += 1;
        self.setHasJustReadRoute();
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

        const eql = std.mem.eql;

        if (eql(u8, "HTTP/1.1", self.previous_bytes.items)) {
            self.request_info.protocol_version = .one_dot_one;
        } else if (eql(u8, "HTTP/2", self.previous_bytes.items)) {
            self.request_info.protocol_version = .two;
        } else if (eql(u8, "HTTP/3", self.previous_bytes.items)) {
            self.request_info.protocol_version = .three;
        } else {
            return RequestReadError.UnsupportedProtocol;
        }

        self.clearPreviousBytes();
        self.cursor_position += 1;
    }

    pub fn clearPreviousBytes(self: *Self) void {
        self.previous_bytes.deinit();

        self.previous_bytes = std.ArrayList(u8).init(self.allocator);
    }

    pub fn setHasJustReadHttpMethod(self: *Self) void {
        self.read_state = .route;
    }

    pub fn setHasJustBegun(self: *Self, has_just_begun: bool) void {
        self.has_just_begun = has_just_begun;
    }

    pub fn setHasJustReadRoute(self: *Self) void {
        self.read_state = .protocol_version;
    }

    pub fn setHasJustReadProtocolVersion(self: *Self) void {
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
    protocol_version: ?ProtocolVersion,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) RequestInfo {
        return Self{
            .request_type = null,
            .route = std.ArrayList(u8).init(allocator),
            .protocol_version = null,
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

const ProtocolVersion = enum {
    one_dot_one,
    two,
    three,
};

const RequestReadError = error{
    UnsupportedProtocol,
};

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

test "HttpRequestReader reports reading a GET request for the \"GET\" string" {
    const request: []const u8 = "GET ";

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    try http_request_reader.readNextBytes(request);

    const request_info = http_request_reader.request_info;

    try std.testing.expectEqual(.get, request_info.request_type);
}

test "HttpRequestReader reports reading a GET request when it is split into multiple strings" {
    const request_first_part: []const u8 = "GE";
    const request_second_part: []const u8 = "T ";

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    try http_request_reader.readNextBytes(request_first_part);
    try http_request_reader.readNextBytes(request_second_part);

    const request_info = http_request_reader.request_info;

    try std.testing.expectEqual(.get, request_info.request_type);
}

const HttpMethodTuple = std.meta.Tuple(&.{ []const u8, RequestType });

test "HttpRequestReader knows all HTTP methods" {
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

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    try http_request_reader.readNextBytes(request);

    const request_info = http_request_reader.request_info;

    try std.testing.expectEqual(tuple[1], request_info.request_type);
}

test "HttpRequestReader reports correct route" {
    const request: []const u8 = "/a/b/c ";

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    http_request_reader.setHasJustReadHttpMethod();

    try http_request_reader.readNextBytes(request);

    for ("/a/b/c", http_request_reader.request_info.route.items) |c1, c2| {
        try std.testing.expectEqual(c1, c2);
    }
}

test "HttpRequestReader reports correct route after reading both request type and route" {
    const request: []const u8 = "GET /a/b/c ";

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    try http_request_reader.readNextBytes(request);

    try std.testing.expectEqual(.get, http_request_reader.request_info.request_type);

    for ("/a/b/c", http_request_reader.request_info.route.items) |c1, c2| {
        try std.testing.expectEqual(c1, c2);
    }
}

test "HttpRequestReader reports reading correct route when it is split" {
    const first_request: []const u8 = "/a/";
    const second_request: []const u8 = "b/c ";

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    http_request_reader.setHasJustReadHttpMethod();

    try http_request_reader.readNextBytes(first_request);
    try http_request_reader.readNextBytes(second_request);

    for ("/a/b/c", http_request_reader.request_info.route.items) |c1, c2| {
        try std.testing.expectEqual(c1, c2);
    }
}

test "HttpRequestReader reports reading correct protocol version" {
    const request: []const u8 = "HTTP/1.1\n";

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    http_request_reader.setHasJustReadRoute();

    try http_request_reader.readNextBytes(request);

    try std.testing.expectEqual(.one_dot_one, http_request_reader.request_info.protocol_version);
}

test "HttpRequestReader reports reading correct protocol version if it is split" {
    const first_request: []const u8 = "HTTP";
    const second_request: []const u8 = "/1.1\n";

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    http_request_reader.setHasJustReadRoute();

    try http_request_reader.readNextBytes(first_request);
    try http_request_reader.readNextBytes(second_request);

    try std.testing.expectEqual(.one_dot_one, http_request_reader.request_info.protocol_version);
}

test "HttpRequestReader reports reading HTTP/2 protocol version" {
    const request: []const u8 = "HTTP/2\n";

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    http_request_reader.setHasJustReadRoute();

    try http_request_reader.readNextBytes(request);

    try std.testing.expectEqual(.two, http_request_reader.request_info.protocol_version);
}

test "HttpRequestReader reports reading HTTP/3 protocol version" {
    const request: []const u8 = "HTTP/3\n";

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    http_request_reader.setHasJustReadRoute();

    try http_request_reader.readNextBytes(request);

    try std.testing.expectEqual(.three, http_request_reader.request_info.protocol_version);
}

test "HttpRequestReader reports error when unsupported protocol version is specified" {
    const request: []const u8 = "HTTP/4\n";

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    http_request_reader.setHasJustReadRoute();

    const result = http_request_reader.readNextBytes(request);

    try std.testing.expectError(RequestReadError.UnsupportedProtocol, result);
}
