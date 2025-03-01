const std = @import("std");
const builtin = @import("builtin");
const zlog = @import("zlog");
const xml = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});
const cfg = @import("config.zig");
const table = @import("table.zig");
const string = []const u8;

pub const parseDocArgs = struct {
    allocator: std.mem.Allocator,
    folder_path: string,
    config: cfg.Config,
};

fn getTags(allocator: std.mem.Allocator, root: *xml.struct__xmlNode, tag_name: string) !std.ArrayList(*xml.struct__xmlNode) {
    var result = std.ArrayList(*xml.struct__xmlNode).init(allocator);

    var child: ?*xml.struct__xmlNode = root.children;
    while (child != null) {
        const ch = child.?;
        if (ch.type == xml.XML_ELEMENT_NODE) {
            const tag = std.mem.span(ch.name);
            const ns = if (ch.ns != null) std.mem.span(ch.ns.*.prefix) else "";

            if (std.mem.eql(u8, tag, tag_name) and std.mem.eql(u8, ns, "w")) {
                try result.append(ch);
            } else {
                const children_result = try getTags(allocator, ch, tag_name);
                try result.appendSlice(children_result.items);
                children_result.deinit();
            }
        }
        child = ch.next;
    }

    return result;
}

fn getPTags(allocator: std.mem.Allocator, root: *xml.struct__xmlNode) !std.ArrayList(*xml.struct__xmlNode) {
    return try getTags(allocator, root, "p");
}

fn getText(allocator: std.mem.Allocator, p_tag: *xml.struct__xmlNode) !string {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var child: ?*xml.struct__xmlNode = p_tag.children;
    while (child != null) {
        const ch = child.?;
        if (ch.type == xml.XML_TEXT_NODE) {
            try result.appendSlice(std.mem.span(ch.content));
        } else {
            const inner_text = try getText(allocator, ch);
            try result.appendSlice(inner_text);
            allocator.free(inner_text);
        }
        child = ch.next;
    }

    return result.toOwnedSlice();
}

const ReplaceArgs = struct {
    allocator: std.mem.Allocator,
    p_tag: *xml.struct__xmlNode,
    p_tag_text: string,
    placeholder: string,
    new_text: string,
};

fn replacePlaceholder(args: ReplaceArgs) !void {
    const t_tags = try getTags(args.allocator, args.p_tag, "t");
    var text = args.p_tag_text;

    var idx_opt = std.mem.indexOf(u8, args.p_tag_text, args.placeholder);
    while (idx_opt != null) {
        var start = idx_opt.?;
        var end = start + args.placeholder.len;

        var i: usize = 0;
        while (i < t_tags.items.len) : (i += 1) {
            const t_tag = t_tags.items[i];
            const child = t_tag.children;
            if (child == null) {
                continue;
            }
            const content = child.?.*.content;
            if (content != null) {
                const inner_text = std.mem.span(content.?);
                if (start >= inner_text.len) {
                    start -= inner_text.len;
                    end -= inner_text.len;
                    continue;
                } else if (start < inner_text.len and end <= inner_text.len) {
                    // Full text replacement inside string
                    text = std.fmt.allocPrint(args.allocator, "{s}{s}{s}", .{ text[0..start], args.new_text, text[end..] }) catch @panic("oom");
                    idx_opt = std.mem.indexOf(u8, text, args.placeholder);
                    const new_inner = std.fmt.allocPrint(args.allocator, "{s}{s}{s}", .{ inner_text[0..start], args.new_text, inner_text[end..] }) catch @panic("oom");
                    xml.xmlNodeSetContent(child, new_inner.ptr);
                } else if (start < text.len and end > text.len) {
                    // We need to replace the start of the placeholder with the new text and in the next valid child trim until the end of the placeholder
                    text = std.fmt.allocPrint(args.allocator, "{s}{s}{s}", .{ text[0..start], args.new_text, text[end..] }) catch @panic("oom");
                    idx_opt = std.mem.indexOf(u8, text, args.placeholder);
                    const new_inner = std.fmt.allocPrint(args.allocator, "{s}{s}", .{ inner_text[0..start], args.new_text }) catch @panic("oom");
                    xml.xmlNodeSetContent(child, new_inner.ptr);
                    end -= inner_text.len;

                    i += 1;
                    var inner_child: [*c]xml.struct__xmlNode = null;
                    while (inner_child == null) : (i += 1) {
                        const inner_t_tag = t_tags.items[i];
                        inner_child = inner_t_tag.children;
                    }
                    i -= 1;

                    const inner_content = child.?.*.content;
                    if (inner_content != null) {
                        const next_inner_text = std.mem.span(inner_content.?);
                        xml.xmlNodeSetContent(inner_child.?, next_inner_text[end..]);
                    }
                } else {
                    @panic("start and end are out of bounds");
                }
            }
        }
    }
    return;
}

pub fn parseDoc(args: parseDocArgs) !void {
    const allocator = args.allocator;
    const folder_path = args.folder_path;

    var placeholders = std.ArrayList([]const u8).init(allocator);
    defer placeholders.deinit();
    var iter = args.config.replaceMap.keyIterator();
    while (iter.next()) |key| {
        try placeholders.append(key.*);
    }

    var folder = try std.fs.openDirAbsolute(folder_path, .{});
    defer folder.close();
    const file = try folder.realpathAlloc(allocator, "word/document.xml");

    const doc = xml.xmlReadFile(file.ptr, null, 0);
    if (doc == null) {
        return error.DocNotReadable;
    }
    defer xml.xmlFreeDoc(doc);

    const root_ptr = xml.xmlDocGetRootElement(doc);
    if (root_ptr == null) {
        return error.RootNotReadable;
    }
    var root = root_ptr.*;

    const p_tags = try getPTags(allocator, &root);
    for (p_tags.items) |p_tag| {
        var text = getText(allocator, p_tag) catch "";
        if (std.mem.eql(u8, text, "")) {
            continue;
        }
        if (std.mem.indexOf(u8, text, "{{") != null) {
            var placeholder_found = true;
            while (placeholder_found) {
                var local_placeholder_found = false;
                for (placeholders.items) |placeholder| {
                    if (std.mem.indexOf(u8, text, placeholder) != null) {
                        const value = args.config.replaceMap.get(placeholder);
                        if (value == null) {
                            continue;
                        }
                        switch (value.?) {
                            .string => |str| {
                                if (std.mem.indexOf(u8, text, placeholder) != null) {
                                    const replaceArgs = ReplaceArgs{
                                        .allocator = allocator, //
                                        .p_tag = p_tag, //
                                        .p_tag_text = text, //
                                        .placeholder = placeholder, //
                                        .new_text = str,
                                    };
                                    try replacePlaceholder(replaceArgs);
                                    local_placeholder_found = true;
                                    break;
                                }
                            },
                            .table => |_| {
                                // Check if the contents of the paragraph is JUST the placeholder
                                if (!std.mem.eql(u8, text, placeholder)) {
                                    zlog.warn("Table replacement will remove the whole paragrah for {s}", .{placeholder});
                                }

                                if (try table.createTable(doc, p_tag.ns)) |table_node| {
                                    p_tag.* = table_node.*;
                                    local_placeholder_found = true;
                                    break;
                                }
                            },
                        }
                    }
                }

                allocator.free(text);
                text = getText(allocator, p_tag) catch "";
                placeholder_found = local_placeholder_found;
            }
        }
    }

    const result = xml.xmlSaveFile(file.ptr, doc);
    if (result == -1) {
        zlog.err("could not save file", .{});
    }

    // TODO: delete me!
    _ = xml.xmlSaveFile("output.xml", doc);

    // TODO: Apply this for the header and footer as well
}
