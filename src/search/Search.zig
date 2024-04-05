const Search = @This();

const std = @import("std");
const Options = @import("../Cli.zig").Options;
const Result = @import("Result.zig");
const Query = @import("Query.zig");
const json = std.json;
const Allocator = std.mem.Allocator;

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

    var query = try Query.init(self.allocator, query_str, options);
    defer query.deinit();

    var buffer: [8096]u8 = undefined;
    var req = try client.open(.GET, query.uri, .{
        .server_header_buffer = &buffer,
        .extra_headers = &.{
            .{ .name = "Accept", .value = "application/vnd.github.text-match+json" },
            .{ .name = "Authorization", .value = token },
            .{ .name = "X-GitHub-Api-Version", .value = "2022-11-28" },
        },
    });
    defer req.deinit();
    try req.send(.{});
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
        &query,
        body,
    );
}
