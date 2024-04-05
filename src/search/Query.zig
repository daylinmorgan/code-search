const Query = @This();

const std = @import("std");
const Options = @import("../Cli.zig").Options;
const Uri = std.Uri;
const Allocator = std.mem.Allocator;

allocator: Allocator,
uri: Uri,

pub fn init(
    allocator: Allocator,
    query_str: *const []u8,
    options: *const Options,
) !Query {
    var uri = Uri.parse("https://api.github.com/search/code") catch unreachable;

    var query = std.ArrayList(u8).init(allocator);
    defer query.deinit();
    try query.appendSlice("q=");
    try query.appendSlice(query_str.*);
    if (options.raw) {
        std.log.debug("using raw search query ignoring other flags", .{});
    } else {
        try query.append(' ');
        inline for (.{
            "user",
            "language",
            "org",
            "repo",
            "path",
            "language",
            "size",
            "filename",
            "extension",
        }) |fld| {
            if (@field(options, fld)) |value| {
                try query.appendSlice(fld ++ ":");
                try query.appendSlice(value);
                try query.append(' ');
            }
        }
        if (options.page) |page| {
            try query.append('&');
            try query.appendSlice("page=");
            const page_str = try std.fmt.allocPrint(allocator, "{d}", .{page});
            defer allocator.free(page_str);
            try query.appendSlice(page_str);
        }
        if (options.@"per-page") |per_page| {
            try query.append('&');
            try query.appendSlice("per_page=");
            const per_page_str = try std.fmt.allocPrint(allocator, "{d}", .{per_page});
            defer allocator.free(per_page_str);
            try query.appendSlice(per_page_str);
        }
    }
    uri.query = try Uri.escapeQuery(allocator, query.items);
    return Query{
        .allocator = allocator,
        .uri = uri,
    };
}

pub fn deinit(self: *Query) void {
    if (self.uri.query) |query| {
        self.allocator.free(query);
    }
}
