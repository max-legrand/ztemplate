const std = @import("std");
const builtin = @import("builtin");

pub fn systemZip(allocator: std.mem.Allocator, input_folder: []const u8, output_file: []const u8) !void {
    switch (builtin.os.tag) {
        .windows => {
            @panic("not implemented");
        },
        .linux, .macos => {
            var child = std.process.Child.init(&[_][]const u8{ "zip", "-q", "-r", output_file, "." }, allocator);
            child.cwd = input_folder;
            _ = try child.spawnAndWait();
        },
        else => {
            @panic("Unsupported OS");
        },
    }
}
