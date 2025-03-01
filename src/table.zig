const std = @import("std");
const xml = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});

pub fn createTable(
    doc: [*c]xml.struct__xmlDoc,
    ns: [*c]xml.struct__xmlNs,
) !?[*c]xml.struct__xmlNode {
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
            // Create two columns with equal width
            for (0..2) |_| {
                if (xml.xmlNewNode(ns, "gridCol")) |gc| {
                    // Don't specify width here, let Word calculate it based on the table width
                    _ = xml.xmlAddChild(grid, gc);
                }
            }
            _ = xml.xmlAddChild(n, grid);
        }

        if (createRow(doc, ns)) |r| {
            _ = xml.xmlAddChild(n, r);
        }
    }

    return node;
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

            // Add top border
            const top = xml.xmlNewNode(ns, @constCast("top"));
            if (top) |t| {
                _ = xml.xmlSetProp(t, "w:val", "single");
                _ = xml.xmlSetProp(t, "w:sz", "8"); // Thicker border (8 instead of 4)
                _ = xml.xmlSetProp(t, "w:space", "0");
                _ = xml.xmlSetProp(t, "w:color", "000000"); // Black color
                _ = xml.xmlAddChild(b, t);
            }

            // Add left border
            const left = xml.xmlNewNode(ns, @constCast("left"));
            if (left) |l| {
                _ = xml.xmlSetProp(l, "w:val", "single");
                _ = xml.xmlSetProp(l, "w:sz", "8");
                _ = xml.xmlSetProp(l, "w:space", "0");
                _ = xml.xmlSetProp(l, "w:color", "000000");
                _ = xml.xmlAddChild(b, l);
            }

            // Add bottom border
            const bottom = xml.xmlNewNode(ns, @constCast("bottom"));
            if (bottom) |bt| {
                _ = xml.xmlSetProp(bt, "w:val", "single");
                _ = xml.xmlSetProp(bt, "w:sz", "8");
                _ = xml.xmlSetProp(bt, "w:space", "0");
                _ = xml.xmlSetProp(bt, "w:color", "000000");
                _ = xml.xmlAddChild(b, bt);
            }

            // Add right border
            const right = xml.xmlNewNode(ns, @constCast("right"));
            if (right) |r| {
                _ = xml.xmlSetProp(r, "w:val", "single");
                _ = xml.xmlSetProp(r, "w:sz", "8");
                _ = xml.xmlSetProp(r, "w:space", "0");
                _ = xml.xmlSetProp(r, "w:color", "000000");
                _ = xml.xmlAddChild(b, r);
            }

            // Add inside horizontal border
            const insideH = xml.xmlNewNode(ns, @constCast("insideH"));
            if (insideH) |ih| {
                _ = xml.xmlSetProp(ih, "w:val", "single");
                _ = xml.xmlSetProp(ih, "w:sz", "8");
                _ = xml.xmlSetProp(ih, "w:space", "0");
                _ = xml.xmlSetProp(ih, "w:color", "000000");
                _ = xml.xmlAddChild(b, ih);
            }

            // Add inside vertical border
            const insideV = xml.xmlNewNode(ns, @constCast("insideV"));
            if (insideV) |iv| {
                _ = xml.xmlSetProp(iv, "w:val", "single");
                _ = xml.xmlSetProp(iv, "w:sz", "8");
                _ = xml.xmlSetProp(iv, "w:space", "0");
                _ = xml.xmlSetProp(iv, "w:color", "000000");
                _ = xml.xmlAddChild(b, iv);
            }

            _ = xml.xmlAddChild(n, borders);
        }

        _ = xml.xmlAddChild(n, style);
        _ = xml.xmlAddChild(n, width);
    }
    return node;
}

fn createRow(doc: [*c]xml.struct__xmlDoc, ns: [*c]xml.struct__xmlNs) ?[*c]xml.struct__xmlNode {
    const row = xml.xmlNewNode(ns, @constCast("tr"));
    if (row) |r| {
        r.*.type = xml.XML_ELEMENT_NODE;
        r.*.doc = doc;

        if (createCell(doc, ns, "1")) |c| {
            _ = xml.xmlAddChild(r, c);
        }

        if (createCell(doc, ns, "2")) |c| {
            _ = xml.xmlAddChild(r, c);
        }
    }
    return row;
}

fn createCell(
    doc: [*c]xml.struct__xmlDoc,
    ns: [*c]xml.struct__xmlNs,
    data: []const u8,
) ?[*c]xml.struct__xmlNode {
    const cell = xml.xmlNewNode(ns, @constCast("tc"));
    if (cell) |c| {
        c.*.type = xml.XML_ELEMENT_NODE;
        c.*.doc = doc;

        // Create cell properties
        const tcPr = xml.xmlNewNode(ns, @constCast("tcPr"));
        if (tcPr) |tp| {
            // Add vertical alignment
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

            // Add paragraph properties for alignment
            // const pPr = xml.xmlNewNode(ns, @constCast("pPr"));
            // if (pPr) |pp| {
            //     const jc = xml.xmlNewNode(ns, @constCast("jc"));
            //     if (jc) |j| {
            //         _ = xml.xmlSetProp(j, "w:val", "center");
            //         _ = xml.xmlAddChild(pp, j);
            //     }
            //     _ = xml.xmlAddChild(p, pp);
            // }

            const run = xml.xmlNewNode(ns, @constCast("r"));
            if (run) |r| {
                r.*.type = xml.XML_ELEMENT_NODE;
                r.*.doc = doc;
                const text = xml.xmlNewNode(ns, @constCast("t"));
                if (text) |t| {
                    t.*.type = xml.XML_ELEMENT_NODE;
                    t.*.doc = doc;

                    // Create a text node with the actual content
                    const text_content = xml.xmlNewText(@constCast(@ptrCast(data.ptr)));
                    if (text_content != null) {
                        _ = xml.xmlAddChild(t, text_content);
                    }

                    _ = xml.xmlAddChild(r, text);
                }
                _ = xml.xmlAddChild(p, r);
            }
            _ = xml.xmlAddChild(c, p);
        }
    }
    return cell;
}
