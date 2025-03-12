const std = @import("std");
const xml = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});
const config = @import("config.zig");
const zlog = @import("zlog");

pub const CreateTableArgs = struct {
    doc: [*c]xml.struct__xmlDoc,
    ns: [*c]xml.struct__xmlNs,
    table: config.Table,
    allocator: std.mem.Allocator,
};

pub fn createTable(
    args: CreateTableArgs,
) !?[*c]xml.struct__xmlNode {
    const data = args.table.table_data;
    if (data.len == 0) {
        return null;
    }

    const cols = data[0].len;
    const ns = args.ns;
    const doc = args.doc;

    const node = xml.xmlNewNode(ns, @constCast("tbl"));
    if (node) |n| {
        n.*.type = xml.XML_ELEMENT_NODE;
        n.*.doc = doc;

        const tbl_pr = createTpr(doc, ns);
        if (tbl_pr) |tp| {
            const res_pr = xml.xmlAddChild(n, tp);
            if (res_pr == null) {
                return error.AddChildFailed;
            }
        }

        if (xml.xmlNewNode(ns, "tblGrid")) |grid| {
            // Create columns
            for (0..cols) |_| {
                if (xml.xmlNewNode(ns, "gridCol")) |gc| {
                    _ = xml.xmlAddChild(grid, gc);
                }
            }
            _ = xml.xmlAddChild(n, grid);
        }

        // Create rows
        for (0..data.len) |row_idx| {
            try createRow(args.allocator, row_idx, args.table, n);
        }
    }

    return node;
}

fn createBorder(
    parent: [*c]xml.struct__xmlNode,
    border_name: []const u8,
) void {
    const border = xml.xmlNewNode(parent.*.ns, @ptrCast(border_name.ptr));
    if (border) |b| {
        _ = xml.xmlSetProp(b, "w:val", "single");
        _ = xml.xmlSetProp(b, "w:sz", "8");
        _ = xml.xmlSetProp(b, "w:space", "0");
        _ = xml.xmlSetProp(b, "w:color", "000000");
        _ = xml.xmlAddChild(parent, b);
    }
}

fn createTpr(
    doc: [*c]xml.struct__xmlDoc,
    ns: [*c]xml.struct__xmlNs,
) ?[*c]xml.struct__xmlNode {
    const node = xml.xmlNewNode(ns, @constCast("tblPr"));
    if (node) |n| {
        n.*.type = xml.XML_ELEMENT_NODE;
        n.*.doc = doc;

        const style = xml.xmlNewNode(ns, @constCast("tblStyle"));
        if (style) |s| {
            s.*.type = xml.XML_ELEMENT_NODE;
            _ = xml.xmlSetProp(s, "w:val", "TableGrid");
        }

        // Set table width to 100% of page width using percentage
        const width = xml.xmlNewNode(ns, @constCast("tblW"));
        if (width) |w| {
            w.*.type = xml.XML_ELEMENT_NODE;
            _ = xml.xmlSetProp(w, "w:w", "5000"); // 5000 = 100%
            _ = xml.xmlSetProp(w, "w:type", "pct"); // Use percentage instead of auto
        }

        // Add borders with thicker lines
        const borders = xml.xmlNewNode(ns, @constCast("tblBorders"));
        if (borders) |b| {
            b.*.type = xml.XML_ELEMENT_NODE;

            const borders_labels = &[_][]const u8{
                "top", "left", "right", "bottom", "insideH", "insideV",
            };
            for (borders_labels) |border_name| {
                createBorder(b, border_name);
            }

            _ = xml.xmlAddChild(n, borders);
        }

        _ = xml.xmlAddChild(n, style);
        _ = xml.xmlAddChild(n, width);
    }
    return node;
}

fn createRow(
    allocator: std.mem.Allocator,
    idx: usize,
    table: config.Table,
    parent: [*c]xml.struct__xmlNode,
) !void {
    const row = xml.xmlNewNode(parent.*.ns, @constCast("tr"));
    if (row) |r| {
        r.*.type = xml.XML_ELEMENT_NODE;
        r.*.doc = parent.*.doc;

        // Create cells for this row
        for (0..table.table_data[idx].len) |col_idx| {
            try createCell(allocator, r, table, idx, col_idx);
        }
    }
    if (xml.xmlAddChild(parent, row) == null) {
        return error.AddChildFailed;
    }
}

fn applyStyle(style: config.Style, wpr: [*c]xml.struct__xmlNode) void {
    if (style.color) |color_value| {
        if (xml.xmlNewNode(wpr.*.ns, "color")) |color_node| {
            color_node.*.type = xml.XML_ELEMENT_NODE;
            color_node.*.doc = wpr.*.doc;
            var out_buf: [6]u8 = undefined;
            _ = std.fmt.formatIntBuf(&out_buf, color_value, 16, .upper, .{});
            _ = xml.xmlSetProp(color_node, "w:val", @constCast(&out_buf));
            _ = xml.xmlAddChild(wpr, color_node);
        }
    }
    if (style.font) |f| {
        switch (f) {
            .normal => {},
            .bold => {
                if (xml.xmlNewNode(wpr.*.ns, "b")) |bold_node| {
                    bold_node.*.type = xml.XML_ELEMENT_NODE;
                    bold_node.*.doc = wpr.*.doc;
                    _ = xml.xmlSetProp(bold_node, "w:val", "true");
                    _ = xml.xmlAddChild(wpr, bold_node);
                }
            },
            .italic => {
                if (xml.xmlNewNode(wpr.*.ns, "i")) |italic_node| {
                    italic_node.*.type = xml.XML_ELEMENT_NODE;
                    italic_node.*.doc = wpr.*.doc;
                    _ = xml.xmlSetProp(italic_node, "w:val", "true");
                    _ = xml.xmlAddChild(wpr, italic_node);
                }
            },
            .italic_bold => {
                if (xml.xmlNewNode(wpr.*.ns, "b")) |bold_node| {
                    bold_node.*.type = xml.XML_ELEMENT_NODE;
                    bold_node.*.doc = wpr.*.doc;
                    _ = xml.xmlSetProp(bold_node, "w:val", "true");
                    _ = xml.xmlAddChild(wpr, bold_node);
                }
                if (xml.xmlNewNode(wpr.*.ns, "i")) |italic_node| {
                    italic_node.*.type = xml.XML_ELEMENT_NODE;
                    italic_node.*.doc = wpr.*.doc;
                    _ = xml.xmlSetProp(italic_node, "w:val", "true");
                    _ = xml.xmlAddChild(wpr, italic_node);
                }
            },
        }
    }
}

fn createCell(
    allocator: std.mem.Allocator,
    parent: [*c]xml.struct__xmlNode,
    table: config.Table,
    row: usize,
    col: usize,
) !void {
    const ns = parent.*.ns;
    const doc = parent.*.doc;
    const cell = xml.xmlNewNode(ns, @constCast("tc"));
    if (cell) |c| {
        c.*.type = xml.XML_ELEMENT_NODE;
        c.*.doc = doc;

        // Create cell properties
        const tcPr = xml.xmlNewNode(ns, @constCast("tcPr"));
        if (tcPr) |tp| {
            const vAlign = xml.xmlNewNode(ns, @constCast("vAlign"));
            if (vAlign) |va| {
                _ = xml.xmlSetProp(va, "w:val", "left");
                _ = xml.xmlAddChild(tp, va);
            }

            _ = xml.xmlAddChild(c, tp);
        }

        // Add text with paragraph properties for alignment
        const paragraph = xml.xmlNewNode(ns, @constCast("p"));
        if (paragraph) |p| {
            p.*.type = xml.XML_ELEMENT_NODE;
            p.*.doc = doc;

            const run = xml.xmlNewNode(ns, @constCast("r"));
            if (run) |r| {
                r.*.type = xml.XML_ELEMENT_NODE;
                r.*.doc = doc;

                if (xml.xmlNewNode(ns, @constCast("rPr"))) |wpr| {
                    wpr.*.type = xml.XML_ELEMENT_NODE;
                    wpr.*.doc = doc;

                    // Apply styles based on priority: cell > row > column
                    if (table.cell_styles.get(.{ row, col })) |style| {
                        applyStyle(style, wpr);
                    } else if (table.row_styles.get(row)) |style| {
                        applyStyle(style, wpr);
                    } else if (table.col_styles.get(col)) |style| {
                        applyStyle(style, wpr);
                    }
                    _ = xml.xmlAddChild(r, wpr);
                }

                const text = xml.xmlNewNode(ns, @constCast("t"));
                if (text) |t| {
                    t.*.type = xml.XML_ELEMENT_NODE;
                    t.*.doc = doc;

                    const cell_content = allocator.dupe(u8, table.table_data[row][col]) catch "";
                    defer allocator.free(cell_content);

                    xml.xmlNodeSetContent(t, @ptrCast(cell_content.ptr));
                    _ = xml.xmlAddChild(r, t);
                }
                _ = xml.xmlAddChild(p, r);
            }
            _ = xml.xmlAddChild(c, p);
        }
    }
    if (xml.xmlAddChild(parent, cell) == null) {
        return error.AddChildFailed;
    }
}
