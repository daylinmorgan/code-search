const Search = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Options = @import("../Cli.zig").Options;

const Result = @import("Result.zig");
const json = std.json;
const Uri = std.Uri;

const Client = std.http.Client;
const Headers = Client.Request.Headers;

allocator: Allocator,

//curl -L \
// -H "Accept: application/vnd.github+json" \
// -H "Authorization: Bearer <YOUR-TOKEN>" \
// -H "X-GitHub-Api-Version: 2022-11-28" \
// "https://api.github.com/search/code?q=Q"

pub fn init(allocator: Allocator) Search {
    return Search{
        .allocator = allocator,
    };
}


fn generateQuery(
    allocator: Allocator,
    query_str: *const []u8,
    options: *const Options,
) ![]const u8 {
    var query = std.ArrayList(u8).init(allocator);
    defer query.deinit();
    try query.appendSlice("q=");
    try query.appendSlice(query_str.*);
    if (options.raw) {
        std.log.debug("using raw search query ignoring other flags", .{});
    } else {
        try query.appendSlice(" ");
        inline for (.{
            "user",
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
                try query.appendSlice(" ");
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

    return query.toOwnedSlice();
}

pub fn fetch(
    self: *Search,
    query_str: *const []u8,
    options: *const Options,
) !Result {
    const tokenEnv = std.process.getEnvVarOwned(self.allocator, "GITHUB_TOKEN") catch |err| {
        std.log.err("{}", .{err});
        std.log.err("GITHUB_TOKEN must be set", .{});
        std.process.exit(1);
    };
    defer self.allocator.free(tokenEnv);
    const token = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{tokenEnv});
    defer self.allocator.free(token);

    var client = Client{ .allocator = self.allocator };
    defer client.deinit();

    const query = try generateQuery(self.allocator, query_str, options);
    defer self.allocator.free(query);

    var uri = try Uri.parse("https://api.github.com/search/code");
    uri.query = Uri.Component {.raw = query};

    var buffer: [8096]u8 = undefined;
    var req = try client.open(.GET, uri, .{
        .server_header_buffer = &buffer,
        .extra_headers = &.{
            .{ .name = "Accept", .value = "application/vnd.github.text-match+json" },
            .{ .name = "Authorization", .value = token },
            .{ .name = "X-GitHub-Api-Version", .value = "2022-11-28" },
        },
    });
    defer req.deinit();
    try req.send();
    try req.wait();
    if (req.response.status != .ok) {
        std.log.err("Request returned {d}: {s}", .{
            req.response.status,
            req.response.status.phrase().?,
        });
        std.process.exit(1);
    }

    const body =
        req.reader().readAllAlloc(self.allocator, std.math.maxInt(usize)) catch unreachable;
    defer self.allocator.free(body);
    return Result.init(
        self.allocator,
        query,
        body,
    );
}
