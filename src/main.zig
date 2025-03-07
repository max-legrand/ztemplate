const std = @import("std");
const zlog = @import("zlog");
const yazap = @import("yazap");
const utils = @import("utils.zig");
const App = yazap.App;
const Arg = yazap.Arg;
const zip = @import("zip.zig");
const xml = @import("xml.zig");
const config = @import("config.zig");

const ztemplate_args = struct {
    output: []const u8,
    data: []const u8,
    template: []const u8,
    force: bool,
};

fn validArgs(matches: yazap.ArgMatches) !ztemplate_args {
    if (!matches.containsArg("output")) return error.MissingOutput;
    if (!matches.containsArg("data")) return error.MissingData;
    if (!matches.containsArg("template")) return error.MissingTemplate;

    const output = matches.getSingleValue("output").?;
    const data = matches.getSingleValue("data").?;
    const template = matches.getSingleValue("template").?;
    const force = matches.containsArg("force");
    return ztemplate_args{
        .output = output,
        .data = data,
        .template = template,
        .force = force,
    };
}

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_name = @tagName(scope);
    if (std.mem.eql(u8, scope_name, "tokenizer") or std.mem.eql(u8, scope_name, "parser")) {
        return;
    }

    // We only recognize 4 log levels in this application.
    const level_txt = switch (level) {
        .err => "error",
        .warn => "warning",
        .info => "info",
        .debug => "debug",
    };
    const prefix1 = level_txt;
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    // Print the message to stderr, silently ignoring any errors
    std.debug.print(prefix1 ++ prefix2 ++ format ++ "\n", args);
}
pub const std_options = std.Options{
    .logFn = log,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    try zlog.initGlobalLogger(.INFO, true, "main", null, null, allocator);
    defer zlog.deinitGlobalLogger();

    var app = App.init(allocator, "ztemplate", "Custom templating tool for word documents");

    var ztemplate = app.rootCommand();
    try ztemplate.addArg(Arg.booleanOption( //
        "verbose", //
        'v', //
        "Enable debug logging"));

    const output_arg = Arg.singleValueOption( //
        "output", //
        'o', //
        "Output file - Must be .docx" //
    );
    try ztemplate.addArg(output_arg);

    const template_arg = Arg.singleValueOption( //
        "template", //
        't', //
        "Template file - Must be .docx" //
    );
    try ztemplate.addArg(template_arg);

    const data_arg = Arg.singleValueOption( //
        "data", //
        'd', //
        "Data file - Must be .yaml/.yml" //
    );
    try ztemplate.addArg(data_arg);

    const force_arg = Arg.booleanOption( //
        "force", //
        'f', //
        "Force overwrite existing output file" //
    );
    try ztemplate.addArg(force_arg);

    const version = app.createCommand("version", "Print the version information");
    try ztemplate.addSubcommand(version);

    const matches = try app.parseProcess();

    if (matches.containsArg("verbose")) {
        zlog.setLevel(.DEBUG);
    }

    const args = validArgs(matches) catch {
        try app.displayHelp();
        return;
    };

    var config_file = args.data;
    if (!utils.isAbsPath(args.data)) {
        config_file = try std.fs.path.join(allocator, &[_][]const u8{ try std.fs.cwd().realpathAlloc(allocator, "."), args.data });
    }
    var cfg = try config.parseConfig(allocator, config_file);
    defer cfg.deinit(allocator);

    if (matches.subcommandMatches("version")) |_| {
        const version_string = try utils.version(allocator);
        zlog.info("Version: {s}", .{version_string});
    }

    const dir = try utils.unzip(args.template, args.force);
    const parseArgs = xml.parseDocArgs{
        .allocator = allocator,
        .folder_path = dir,
        .config = cfg,
    };
    try xml.parseDoc(parseArgs);

    var output = args.output;
    if (!utils.isAbsPath(output)) {
        const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");

        const isAbs = utils.isAbsPath(output);
        if (!isAbs) {
            output = try std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ cwd_path, output });
        }
    }

    try zip.systemZip(allocator, dir, output);
    try std.fs.deleteTreeAbsolute(dir);
}
