const std = @import("std");
const Yaml = @import("yaml").Yaml;
const zlog = @import("zlog");
const utils = @import("utils.zig");

const FontStyle = enum {
    normal,
    bold,
    italic,
    italic_bold,
    fn fromString(str: []const u8) ?FontStyle {
        if (std.mem.eql(u8, str, "normal")) return .normal;
        if (std.mem.eql(u8, str, "bold")) return .bold;
        if (std.mem.eql(u8, str, "italic")) return .italic;
        if (std.mem.eql(u8, str, "italic_bold")) return .italic_bold;
        return null;
    }
};

fn parseColor(str: []const u8) ?usize {
    const first_char = str[0];
    if (first_char == '#') {
        return std.fmt.parseInt(usize, str[1..], 16) catch return null;
    } else {
        return std.fmt.parseInt(usize, str, 16) catch return null;
    }
}

pub const Style = struct {
    // Font style to be used, defaults to normal if not provided.
    font: ?FontStyle,
    // Color to be used, defaults to automatic color if not provided.
    color: ?usize,
};

const Tuple = std.meta.Tuple;
const Coordinate = Tuple(&[_]type{ usize, usize });

pub const Table = struct {
    data_file: []const u8,
    table_data: [][][]const u8,
    row_styles: std.AutoHashMap(usize, Style),
    col_styles: std.AutoHashMap(usize, Style),
    cell_styles: std.AutoHashMap(Coordinate, Style),

    fn deinit(self: *Table, allocator: std.mem.Allocator) void {
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

        self.row_styles.deinit();
        self.col_styles.deinit();
        self.cell_styles.deinit();
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
                .table => |*table| {
                    table.deinit(allocator);
                },
            }
            allocator.free(entry.key_ptr.*);
        }
        self.replaceMap.deinit();
    }
};

pub fn parseConfig(allocator: std.mem.Allocator, path: []const u8) !Config {
    const file_data = try std.fs.openFileAbsolute(path, .{});
    defer file_data.close();
    const data = try file_data.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    var yaml: Yaml = .{ .source = data };
    defer yaml.deinit(allocator);
    try yaml.load(allocator);

    if (yaml.docs.items.len == 0) {
        return error.NoDocs;
    }

    const top_level = yaml.docs.items[0].map;
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
                allocator.free(owned_file);
                owned_file = joined_path;
            }

            const file_object = try std.fs.openFileAbsolute(owned_file, .{});
            defer file_object.close();
            const fdata = try file_object.readToEndAlloc(allocator, std.math.maxInt(usize));
            defer allocator.free(fdata);

            // Parse the CSV data safely
            var rows = std.ArrayList([][]const u8).init(allocator);
            defer rows.deinit();
            var lines = std.mem.splitScalar(u8, fdata, '\n');
            while (lines.next()) |line| {
                if (line.len == 0) continue; // Skip empty lines

                var cols = std.ArrayList([]const u8).init(allocator);
                defer cols.deinit();
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

            var row_styles = std.AutoHashMap(usize, Style).init(allocator);
            var col_styles = std.AutoHashMap(usize, Style).init(allocator);
            var cell_styles = std.AutoHashMap(Coordinate, Style).init(allocator);
            // Indexs provided are 1-indexed, so we will subtract 1 to ensure they are properly applied.
            if (table_map.get("styles")) |s| {
                const styles = try s.asMap();
                if (styles.get("rows")) |r| {
                    const row_style_items = try r.asList();
                    for (row_style_items) |row_style_item| {
                        const map = try row_style_item.asMap();
                        const idx: usize = @intCast(try map.get("index").?.asInt());
                        var f_style: ?FontStyle = null;
                        if (map.get("font")) |fs| {
                            const fs_str = try fs.asString();
                            f_style = FontStyle.fromString(fs_str);
                            if (f_style == null) {
                                zlog.warn("Font style was invalid. Must be one of \"normal\", \"bold\", \"italic\", or \"italic_bold\"", .{});
                            }
                        }
                        var color: ?usize = null;
                        if (map.get("color")) |color_value| {
                            const color_str = try color_value.asString();
                            color = parseColor(color_str);
                            if (color == null) {
                                zlog.warn("Color {s} was invalid", .{color_str});
                            }
                        }
                        const style = Style{
                            .font = f_style,
                            .color = color,
                        };
                        try row_styles.put(idx - 1, style);
                    }
                }
                if (styles.get("cols")) |c| {
                    const col_style_items = try c.asList();
                    for (col_style_items) |col_style_item| {
                        const map = try col_style_item.asMap();
                        const idx: usize = @intCast(try map.get("index").?.asInt());
                        var f_style: ?FontStyle = null;
                        if (map.get("font")) |fs| {
                            const fs_str = try fs.asString();
                            f_style = FontStyle.fromString(fs_str);
                            if (f_style == null) {
                                zlog.warn("Font style was invalid. Must be one of \"normal\", \"bold\", \"italic\", or \"italic_bold\"", .{});
                            }
                        }
                        var color: ?usize = null;
                        if (map.get("color")) |color_value| {
                            const color_str = try color_value.asString();
                            color = parseColor(color_str);
                            if (color == null) {
                                zlog.warn("Color {s} was invalid", .{color_str});
                            }
                        }
                        const style = Style{
                            .font = f_style,
                            .color = color,
                        };
                        try col_styles.put(idx - 1, style);
                    }
                }
                if (styles.get("cells")) |c| {
                    const cell_style_items = try c.asList();
                    for (cell_style_items) |cell_style_item| {
                        const map = try cell_style_item.asMap();
                        const idx_string = try map.get("index").?.asString();
                        var items = std.mem.splitScalar(u8, idx_string, ',');
                        const row = std.fmt.parseInt(usize, items.next().?, 10) catch return error.InvalidCellIndex;
                        const col = std.fmt.parseInt(usize, items.next().?, 10) catch return error.InvalidCellIndex;
                        const idx = Coordinate{ row - 1, col - 1 };
                        var f_style: ?FontStyle = null;
                        if (map.get("font")) |fs| {
                            const fs_str = try fs.asString();
                            f_style = FontStyle.fromString(fs_str);
                            if (f_style == null) {
                                zlog.warn("Font style was invalid. Must be one of \"normal\", \"bold\", \"italic\", or \"italic_bold\"", .{});
                            }
                        }
                        var color: ?usize = null;
                        if (map.get("color")) |color_value| {
                            const color_str = try color_value.asString();
                            color = parseColor(color_str);
                            if (color == null) {
                                zlog.warn("Color {s} was invalid", .{color_str});
                            }
                        }
                        const style = Style{
                            .font = f_style,
                            .color = color,
                        };
                        try cell_styles.put(idx, style);
                    }
                }
            }

            // Create the final table data
            const table_data = try allocator.dupe([][]const u8, rows.items);

            try config.replaceMap.put(owned_key, .{
                .table = Table{
                    .data_file = owned_file,
                    .table_data = table_data,
                    .row_styles = row_styles,
                    .col_styles = col_styles,
                    .cell_styles = cell_styles,
                },
            });
        }
    }

    return config;
}
