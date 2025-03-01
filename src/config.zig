const std = @import("std");
const yaml = @import("yaml");
const zlog = @import("zlog");
const utils = @import("utils.zig");

const Table = struct {
    data_file: []const u8,
    table_data: [][][]const u8,

    fn deinit(self: Table, allocator: std.mem.Allocator) void {
        // Free the data_file string
        allocator.free(self.data_file);

        if (self.table_data.len == 0) return;
        // Free each row and its contents
        for (self.table_data) |row| {
            for (row) |col| {
                // Only free if the column is not empty
                if (col.len > 0) {
                    allocator.free(col);
                }
            }
            // Free the row array itself
            allocator.free(row);
        }
        // Free the outer table_data array
        allocator.free(self.table_data);
    }

    fn toJson(self: Table, allocator: std.mem.Allocator) ![]const u8 {
        var json = std.ArrayList(u8).init(allocator);
        try json.appendSlice("{\"data_file\":\"");
        try json.appendSlice(self.data_file);
        try json.appendSlice("\",\"table_data\":[");
        for (self.table_data) |row| {
            try json.appendSlice("[");
            for (row) |col| {
                try json.appendSlice("\"");
                try json.appendSlice(col);
                try json.appendSlice("\",");
            }
            _ = json.pop();
            try json.appendSlice("],");
        }
        _ = json.pop();
        try json.appendSlice("]");
        return json.items;
    }
};

pub const ValueType = enum { string, table };

pub const Value = union(ValueType) {
    string: []const u8,
    table: Table,
};

pub const Config = struct {
    replaceMap: std.StringHashMap(Value),

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        var iter = self.replaceMap.iterator();
        while (iter.next()) |entry| {
            switch (entry.value_ptr.*) {
                .string => |str| {
                    allocator.free(str);
                },
                .table => |table| {
                    table.deinit(allocator);
                },
            }
            allocator.free(entry.key_ptr.*);
        }
        self.replaceMap.deinit();
    }

    pub fn toJson(self: Config, allocator: std.mem.Allocator) ![]const u8 {
        var json = std.ArrayList(u8).init(allocator);
        try json.appendSlice("{");
        var iter = self.replaceMap.iterator();
        while (iter.next()) |entry| {
            switch (entry.value_ptr.*) {
                .string => |str| {
                    try json.appendSlice("\"");
                    try json.appendSlice(entry.key_ptr.*);
                    try json.appendSlice("\":\"");
                    try json.appendSlice(str);
                    try json.appendSlice("\",");
                },
                .table => |t| {
                    try json.appendSlice("\"");
                    try json.appendSlice(entry.key_ptr.*);
                    try json.appendSlice("\":");
                    try json.appendSlice(try t.toJson(allocator));
                    try json.appendSlice(",");
                },
            }
        }
        // Remove the last comma
        _ = json.pop();
        try json.appendSlice("}");
        return json.items;
    }
};

pub fn parseConfig(allocator: std.mem.Allocator, path: []const u8) !Config {
    const file_data = try std.fs.openFileAbsolute(path, .{});
    defer file_data.close();
    const data = try file_data.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    var yaml_data = try yaml.Yaml.load(allocator, data);
    defer yaml_data.deinit(allocator);

    if (yaml_data.docs.items.len == 0) {
        return error.NoDocs;
    }

    const top_level = yaml_data.docs.items[0].map;
    var config = Config{ .replaceMap = std.StringHashMap(Value).init(allocator) };
    for (top_level.keys()) |key| {
        const isString = top_level.get(key).?.asString();
        const owned_key = try std.fmt.allocPrint(allocator, "{{{{{s}}}}}", .{key});
        if (isString) |str| {
            const owned_value = try allocator.dupe(u8, str);
            try config.replaceMap.put(owned_key, .{ .string = owned_value });
        } else |_| {
            const table_map = try top_level.get(key).?.asMap();
            const data_file = try table_map.get("file").?.asString();
            var owned_file = try allocator.dupe(u8, data_file);
            if (!utils.isAbsPath(owned_file)) {
                const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
                defer allocator.free(cwd_path);

                const joined_path = try std.fs.path.join(allocator, &[_][]const u8{ cwd_path, owned_file });
                allocator.free(owned_file); // Free the old path
                owned_file = joined_path;
            }

            const file_object = try std.fs.openFileAbsolute(owned_file, .{});
            defer file_object.close();
            const fdata = try file_object.readToEndAlloc(allocator, std.math.maxInt(usize));
            defer allocator.free(fdata);

            // Parse the CSV data safely
            var rows = std.ArrayList([][]const u8).init(allocator);
            var lines = std.mem.splitScalar(u8, fdata, '\n');
            while (lines.next()) |line| {
                if (line.len == 0) continue; // Skip empty lines

                var cols = std.ArrayList([]const u8).init(allocator);
                var col_iter = std.mem.splitScalar(u8, line, ',');
                while (col_iter.next()) |col| {
                    if (col.len == 0) continue;
                    // Make a copy of the column data
                    const owned_col = try allocator.dupe(u8, col);
                    try cols.append(owned_col);
                }

                // Create a slice for the row
                const row_slice = try allocator.dupe([]const u8, cols.items);
                try rows.append(row_slice);
            }

            // Create the final table data
            const table_data = try allocator.dupe([][]const u8, rows.items);

            try config.replaceMap.put(owned_key, .{ .table = Table{
                .data_file = owned_file,
                .table_data = table_data,
            } });
        }
    }

    return config;
}
