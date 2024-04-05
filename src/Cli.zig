const Cli = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const args = @import("zig-args");
const ViewFormat = @import("search/Result.zig").ViewFormat;

allocator: Allocator,
options: args.ParseArgsResult(Options, null),

pub const Options = struct {
    // query parameters
    in: ?enum { file, path, @"file,path" } = null,
    user: ?[]const u8 = null,
    org: ?[]const u8 = null,
    repo: ?[]const u8 = null,
    path: ?[]const u8 = null,
    language: ?[]const u8 = null,
    size: ?[]const u8 = null,
    filename: ?[]const u8 = null,
    extension: ?[]const u8 = null,

    page: ?u8 = 1,
    @"per-page": ?u8 = 10,
    raw: bool = false,
    help: bool = false,
    format: ?ViewFormat = .markdown,

    pub const shorthands = .{
        .u = "user",
        .o = "org",
        .r = "repo",
        .p = "path",
        .l = "language",
        .s = "size",
        .f = "filename",
        .e = "extension",
        .h = "help",
    };
};

pub fn parse(allocator: Allocator) !Cli {
    const options =
        args.parseForCurrentProcess(Options, allocator, .print) catch {
        fatalHelp();
    };

    if (options.options.help) {
        showHelp();
        std.process.exit(0);
    }

    if (options.positionals.len == 0) {
        std.log.err("must provide search query", .{});
        fatalHelp();
    }

    return Cli{
        .allocator = allocator,
        .options = options,
    };
}

pub fn deinit(self: *Cli) void {
    self.options.deinit();
}

pub fn fatalHelp() noreturn {
    showHelp();
    std.process.exit(1);
}

pub fn showHelp() void {
    std.debug.print(
        \\code-searcher [opts] <search-query>
        \\
        \\  -h, --help      show this help
        \\      --raw       treat input as raw query
        \\      --format    output format, one of: markdown|plain
        \\      --page      page of results to return
        \\      --per-page  numble of results per page (default: 10)
        \\
        \\key/value query options:
        \\      --in        one of: file|path|file,path
        \\  -l, --language
        \\  -u, --user
        \\  -o, --org
        \\      --size
        \\  -f, --filename
        \\  -p, --path
        \\  -e, --extension
        \\
    , .{});
}
