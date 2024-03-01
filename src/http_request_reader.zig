const std = @import("std");

pub const HttpRequestReader = struct {
    request_info: *RequestInfo,
    allocator: std.mem.Allocator,
    previous_bytes: std.ArrayList(u8),
    cursor_position: usize,
    strings_to_request_types: std.StringHashMap(RequestType),
    read_state: ReadState,
    should_continue_reading: bool,

    const Self = @This();

    const Node = std.DoublyLinkedList(u8).Node;

    pub fn init(allocator: std.mem.Allocator) !Self {
        const request_info = try allocator.create(RequestInfo);

        request_info.request_type = null;
        request_info.route = null;

        const previous_bytes = std.ArrayList(u8).init(allocator);

        var strings_to_request_types = std.StringHashMap(RequestType).init(allocator);

        try insertStringRequestTypes(&strings_to_request_types);

        return Self{
            .allocator = allocator,
            .request_info = request_info,
            .previous_bytes = previous_bytes,
            .strings_to_request_types = strings_to_request_types,
            .cursor_position = 0,
            .read_state = .start,
            .should_continue_reading = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.request_info.route) |route| {
            route.deinit();
        }

        self.allocator.destroy(self.request_info);
        self.strings_to_request_types.deinit();
        self.previous_bytes.deinit();
    }

    pub fn readNextBytes(self: *Self, next_bytes: []const u8) !void {
        self.cursor_position = 0;

        self.setShouldContinueReading(true);

        while (self.shouldContinueReading()) {
            switch (self.read_state) {
                .start => try self.readHttpMethod(next_bytes),

                .http_method => try self.readRoute(next_bytes),

                else => break,
            }
        }
    }

    fn readHttpMethod(self: *Self, next_bytes: []const u8) !void {
        var has_read_whole_http_method = false;

        for (next_bytes, self.cursor_position..) |byte, cursor_position| {
            if (byte == ' ') {
                self.cursor_position = cursor_position;
                has_read_whole_http_method = true;
                break;
            }

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

        for (next_bytes[self.cursor_position..], self.cursor_position..) |byte, cursor_position| {
            if (byte == ' ') {
                has_read_whole_route = true;
                self.cursor_position = cursor_position;
                break;
            }

            try self.previous_bytes.append(byte);
        }

        if (!has_read_whole_route) {
            self.setShouldContinueReading(false);
            return;
        }

        self.request_info.route = std.ArrayList(u8).init(self.allocator);

        try self.request_info.route.?.appendSlice(self.previous_bytes.items);

        self.cursor_position += 1;
        self.setHasJustReadRoute();
        self.clearPreviousBytes();
    }

    pub fn clearPreviousBytes(self: *Self) void {
        self.previous_bytes.deinit();

        self.previous_bytes = std.ArrayList(u8).init(self.allocator);
    }

    pub fn setHasJustReadHttpMethod(self: *Self) void {
        self.read_state = .http_method;
    }

    fn hasJustReadHttpMethod(self: *Self) bool {
        return self.read_state == .http_method;
    }

    pub fn setHasJustBegun(self: *Self, has_just_begun: bool) void {
        self.has_just_begun = has_just_begun;
    }

    fn hasJustBegun(self: *Self) bool {
        return self.read_state == .start;
    }

    pub fn setHasJustReadRoute(self: *Self) void {
        self.read_state = .route;
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

const RequestInfo = struct {
    request_type: ?RequestType,
    route: ?std.ArrayList(u8),
};

const ReadState = enum {
    start,
    http_method,
    route,
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

    for ("/a/b/c", http_request_reader.request_info.route.?.items) |c1, c2| {
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

    for ("/a/b/c", http_request_reader.request_info.route.?.items) |c1, c2| {
        try std.testing.expectEqual(c1, c2);
    }
}
