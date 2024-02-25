const std = @import("std");

pub fn main() !void {
    var buf: [100000]u8 = undefined;

    var socket = std.net.StreamServer.init(.{});

    const address = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 1234);

    _ = try socket.listen(address);

    const client = try socket.accept();
    const stream = client.stream;

    _ = try stream.read(&buf);

    const stdout_writer = std.io.getStdOut().writer();

    try stdout_writer.print("Read:\n{s}\n", .{buf});
}
