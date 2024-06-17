const std = @import("std");

pub fn main() !void {
    var buf: [100000]u8 = undefined;

    const address = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 4321);

    var server = try address.listen(.{});

    while (true) {
        var socket = try server.accept();

        _ = try socket.stream.read(&buf);

        std.debug.print("Read:\n{s}\n\n", .{buf});

        socket.stream.close();
    }
}
