const std = @import("std");
const builtin = @import("builtin");

const LocalFileHeader = extern struct {
    signature: [4]u8 align(1) = [4]u8{ 'P', 'K', 3, 4 },
    version_needed_to_extract: u16 align(1) = 20,
    flags: u16 align(1) = 0,
    compression_method: u16 align(1) = 0,
    last_modification_time: u16 align(1),
    last_modification_date: u16 align(1),
    crc32: u32 align(1),
    compressed_size: u32 align(1),
    uncompressed_size: u32 align(1),
    filename_len: u16 align(1),
    extra_len: u16 align(1) = 0,
};

const CentralDirectoryFileHeader = extern struct {
    signature: [4]u8 align(1) = [4]u8{ 'P', 'K', 1, 2 },
    version_made_by: u16 align(1) = 20,
    version_needed_to_extract: u16 align(1) = 20,
    flags: u16 align(1) = 0,
    compression_method: u16 align(1) = 0,
    last_modification_time: u16 align(1),
    last_modification_date: u16 align(1),
    crc32: u32 align(1),
    compressed_size: u32 align(1),
    uncompressed_size: u32 align(1),
    filename_len: u16 align(1),
    extra_len: u16 align(1) = 0,
    comment_len: u16 align(1) = 0,
    disk_number: u16 align(1) = 0,
    internal_file_attributes: u16 align(1) = 0,
    external_file_attributes: u32 align(1) = 0,
    local_file_header_offset: u32 align(1),
};

const EndRecord = extern struct {
    signature: [4]u8 align(1) = [4]u8{ 'P', 'K', 5, 6 },
    disk_number: u16 align(1) = 0,
    central_directory_disk_number: u16 align(1) = 0,
    record_count_disk: u16 align(1),
    record_count_total: u16 align(1),
    central_directory_size: u32 align(1),
    central_directory_offset: u32 align(1),
    comment_len: u16 align(1) = 0,
};

fn writeLocalFileHeader(writer: anytype, filename: []const u8, crc32: u32, uncompressed_size: u32) !void {
    var header: LocalFileHeader = .{
        .last_modification_time = 0,
        .last_modification_date = 0,
        .crc32 = crc32,
        .compressed_size = uncompressed_size,
        .uncompressed_size = uncompressed_size,
        .filename_len = @intCast(filename.len),
    };
    try writer.writeAll(std.mem.asBytes(&header));
    try writer.writeAll(filename);
}

fn writeCentralDirectoryFileHeader(writer: anytype, filename: []const u8, crc32: u32, uncompressed_size: u32, local_file_header_offset: u32) !void {
    var header: CentralDirectoryFileHeader = .{
        .last_modification_date = 0,
        .last_modification_time = 0,
        .crc32 = crc32,
        .compressed_size = uncompressed_size,
        .uncompressed_size = uncompressed_size,
        .filename_len = @intCast(filename.len),
        .local_file_header_offset = local_file_header_offset,
    };
    try writer.writeAll(std.mem.asBytes(&header));
    try writer.writeAll(filename);
}

fn writeEndRecord(writer: anytype, record_count: u16, central_directory_size: u32, central_directory_offset: u32) !void {
    var record = EndRecord{
        .record_count_disk = record_count,
        .record_count_total = record_count,
        .central_directory_size = central_directory_size,
        .central_directory_offset = central_directory_offset,
    };
    try writer.writeAll(std.mem.asBytes(&record));
}

pub fn zipDirectory(allocator: std.mem.Allocator, dir_path: []const u8, output_zip_path: []const u8, flat: bool) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var output_file = try std.fs.cwd().createFile(output_zip_path, .{});
    defer output_file.close();

    var writer = output_file.writer();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var local_file_headers = std.ArrayList(u32).init(allocator);
    defer local_file_headers.deinit();

    var file_paths = std.ArrayList([]const u8).init(allocator);
    defer {
        for (file_paths.items) |path| allocator.free(path);
        file_paths.deinit();
    }

    while (try walker.next()) |entry| {
        const file_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.path });
        try file_paths.append(file_path);

        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const file_info = try file.stat();

        // Handle directories
        if (file_info.kind == .directory) {
            var filename: []const u8 = try std.fmt.allocPrint(allocator, "{s}/", .{entry.path});
            if (flat) {
                filename = try std.fmt.allocPrint(allocator, "{s}/", .{std.fs.path.basename(entry.path)});
            }
            defer if (flat) allocator.free(filename);

            const crc32 = std.hash.Crc32.hash(&.{});
            const local_file_header_offset = try output_file.getPos();
            try writeLocalFileHeader(writer, filename, crc32, 0);
            try local_file_headers.append(@intCast(local_file_header_offset));
            continue;
        }

        // Handle regular files
        const file_data = try allocator.alloc(u8, file_info.size);
        defer allocator.free(file_data);

        _ = try file.readAll(file_data);

        var filename: []const u8 = entry.path;
        if (flat) {
            filename = std.fs.path.basename(entry.path);
        }

        const crc32 = std.hash.Crc32.hash(file_data);
        const local_file_header_offset = try output_file.getPos();
        try writeLocalFileHeader(writer, filename, crc32, @intCast(file_info.size));
        try writer.writeAll(file_data);

        try local_file_headers.append(@intCast(local_file_header_offset));
    }

    const central_directory_offset: u32 = @intCast(try output_file.getPos());
    for (file_paths.items, local_file_headers.items) |file_path, local_file_header_offset| {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const file_info = try file.stat();

        // Handle directories
        if (file_info.kind == .directory) {
            var filename: []const u8 = try std.fmt.allocPrint(allocator, "{s}/", .{file_path});
            if (flat) {
                filename = try std.fmt.allocPrint(allocator, "{s}/", .{std.fs.path.basename(file_path)});
            }
            defer if (flat) allocator.free(filename);

            const crc32 = std.hash.Crc32.hash(&.{});
            try writeCentralDirectoryFileHeader(writer, filename, crc32, 0, local_file_header_offset);
            continue;
        }

        // Handle regular files
        const file_data = try allocator.alloc(u8, file_info.size);
        defer allocator.free(file_data);

        _ = try file.readAll(file_data);

        var filename: []const u8 = file_path;
        if (flat) {
            filename = std.fs.path.basename(file_path);
        }

        const crc32 = std.hash.Crc32.hash(file_data);
        try writeCentralDirectoryFileHeader(writer, filename, crc32, @intCast(file_info.size), local_file_header_offset);
    }

    const central_directory_size: u32 = @intCast(try output_file.getPos() - central_directory_offset);
    try writeEndRecord(writer, @intCast(local_file_headers.items.len), central_directory_size, central_directory_offset);
}

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
