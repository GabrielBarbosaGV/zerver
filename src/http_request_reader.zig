const std = @import("std");

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
    route: ?[]const u8,
};

const HttpRequestReader = struct {
    request_info: *RequestInfo,
    allocator: std.mem.Allocator,
    previous_bytes: std.ArrayList(u8),
    cursor_position: u32,
    strings_to_request_types: std.StringHashMap(RequestType),
    has_just_read_http_method: bool,
    has_just_begun: bool,

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
            .has_just_read_http_method = false,
            .has_just_begun = true,
            .cursor_position = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self.request_info);
        self.strings_to_request_types.deinit();
        self.previous_bytes.deinit();
    }

    pub fn readNextBytes(self: *Self, next_bytes: []const u8) !void {
        if (self.hasJustReadHttpMethod()) {
            self.clearPreviousBytes();

            for (next_bytes) |next_byte| {
                if (next_byte == ' ')
                    break;

                try self.previous_bytes.append(next_byte);
            }

            self.request_info.route = self.previous_bytes.items;
        } else if (self.hasJustBegun()) {
            for (next_bytes) |next_byte| {
                if (next_byte == ' ')
                    break;

                try self.previous_bytes.append(next_byte);
            }

            const string = self.previous_bytes.items;

            if (self.strings_to_request_types.get(string)) |item| {
                self.request_info.request_type = item;
            }
        }
    }

    pub fn clearPreviousBytes(self: *Self) void {
        self.previous_bytes.deinit();

        self.previous_bytes = std.ArrayList(u8).init(self.allocator);
    }

    pub fn setHasJustReadHttpMethod(self: *Self, has_just_read_http_method: bool) void {
        self.has_just_read_http_method = has_just_read_http_method;
    }

    pub fn hasJustReadHttpMethod(self: *Self) bool {
        return self.has_just_read_http_method;
    }

    pub fn setHasJustBegun(self: *Self, has_just_begun: bool) void {
        self.has_just_begun = has_just_begun;
    }

    pub fn hasJustBegun(self: *Self) bool {
        return self.has_just_begun;
    }
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
    const request: []const u8 = "GET";

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    try http_request_reader.readNextBytes(request);

    const request_info = http_request_reader.request_info;

    try std.testing.expectEqual(.get, request_info.request_type);
}

test "HttpRequestReader reports reading a GET request when it is split into multiple strings" {
    const request_first_part: []const u8 = "GE";
    const request_second_part: []const u8 = "T";

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
    const request = tuple[0];

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    try http_request_reader.readNextBytes(request);

    const request_info = http_request_reader.request_info;

    try std.testing.expectEqual(tuple[1], request_info.request_type);
}

test "HttpRequestReader reports correct route" {
    const request: []const u8 = "/a/b/c";

    const allocator = std.testing.allocator;

    var http_request_reader = try HttpRequestReader.init(allocator);
    defer http_request_reader.deinit();

    http_request_reader.setHasJustReadHttpMethod(true);

    try http_request_reader.readNextBytes(request);

    for (request, http_request_reader.request_info.route.?) |c1, c2| {
        try std.testing.expectEqual(c1, c2);
    }
}
