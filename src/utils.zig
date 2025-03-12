const std = @import("std");
const builtin = @import("builtin");
const zlog = @import("zlog");
const xml = @import("zig-xml");

const major = 0;
const minor = 0;
const patch = 1;

const string = []const u8;

pub fn version(allocator: std.mem.Allocator) !string {
    return try std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{ major, minor, patch });
}

pub fn isAbsPath(path: string) bool {
    if (path.len == 0) return false;

    if (builtin.os.tag == .windows) {
        if (path.len >= 2 and std.ascii.isAscii(path[0]) and path[1] == ':') {
            return true;
        }

        if (path.len >= 2 and path[0] == '\\' and path[1] == '\\') {
            return true;
        }
    } else {
        if (path[0] == '/') {
            return true;
        }
    }
    return false;
}

/// Unzip a word document to a folder
pub fn unzip(path: string, force: bool) !string {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get the basename of the path
    var split = std.mem.splitSequence(u8, path, ".docx");
    const basename = split.next().?;
    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");

    const isAbs = isAbsPath(basename);
    const basepath = if (isAbs)
        basename
    else
        try std.fs.path.join(std.heap.page_allocator, &[_]string{ cwd_path, basename });

    const realpath = if (isAbs)
        path
    else
        try std.fs.path.join(std.heap.page_allocator, &[_]string{ cwd_path, path });

    if (force) {
        // Remove the folder if it exists
        var fexists = true;
        _ = std.fs.openDirAbsolute(basepath, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    fexists = false;
                },
                else => return err,
            }
        };

        if (fexists) {
            try std.fs.deleteTreeAbsolute(basepath);
        }
    }
    std.fs.makeDirAbsolute(basepath) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                zlog.err("{s} already exists!", .{path});
                std.process.exit(1);
            },
            else => return err,
        }
    };

    // Unzip the docx file into the folder.
    var dir = try std.fs.openDirAbsolute(basepath, .{});
    defer dir.close();

    var file = try std.fs.openFileAbsolute(realpath, .{ .mode = .read_only });
    defer file.close();
    const stream = file.seekableStream();

    try std.zip.extract(dir, stream, .{});
    return basepath;
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

pub fn exists(path: string) bool {
    if (std.fs.path.isAbsolute(path)) {
        std.fs.accessAbsolute(path, .{}) catch return false;
        return true;
    } else {
        var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
        defer {
            if (gpa.deinit() == .leak) @panic("memory leaked!");
        }
        const allocator = gpa.allocator();
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a_alloc = arena.allocator();

        const abs_path = std.fs.cwd().realpathAlloc(a_alloc, path) catch @panic("Unable to allocate memory for absolute path");
        std.fs.accessAbsolute(abs_path, .{}) catch return false;
        return true;
    }
}
