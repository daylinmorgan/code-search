const Result = @This();
const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const Query = @import("Query.zig");

allocator: Allocator,
_parsed_json: std.json.Parsed(SearchResult),
result: SearchResult,
url: []const u8,

pub const SearchResult = struct {
    total_count: u64,
    incomplete_results: bool,
    items: []SearchResultItem,
};

pub const SearchTextMatch = struct {
    fragment: []const u8,
};

pub const Repository = struct {
    full_name: []const u8,
};

pub const SearchResultItem = struct {
    name: []const u8,
    path: []const u8,
    html_url: []const u8,
    repository: Repository,
    score: f64,
    text_matches: []SearchTextMatch,
};

pub fn init(allocator: Allocator, query: *Query, body: []const u8) !Result {
    const parsed_json = try json.parseFromSlice(
        SearchResult,
        allocator,
        body,
        .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        },
    );

    return Result{
        .allocator = allocator,
        ._parsed_json = parsed_json,
        .result = parsed_json.value,
        .url = try std.fmt.allocPrint(allocator, "{any}", .{query.uri}),
    };
}

pub fn deinit(self: *Result) void {
    self._parsed_json.deinit();
    self.allocator.free(self.url);
}

pub const ViewFormat = enum { markdown, plain };

pub fn view(self: *Result, format: ViewFormat) !void {
    switch (format) {
        .markdown => try self.viewMarkdown(),
        .plain => try self.viewPlain(),
    }
}

pub fn viewPlain(self: *Result) !void {
    const noColor = std.process.getEnvVarOwned(self.allocator, "GITHUB_TOKEN") catch "";
    defer self.allocator.free(noColor);

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\query:
        \\  url: {s}
        \\  total items: {d}
        \\
    , .{ self.url, self.result.total_count });

    for (self.result.items) |item| {
        if (!std.mem.eql(u8, noColor, "")) {
            try stdout.print(
                "\n\x1B[32;1m{s}\x1B[0m - \x1B[36;1m{s}\x1B[0m\n\x1B[2m{s}\x1B[0m\n",
                .{ item.repository.full_name, item.path, item.html_url },
            );
        } else {
            try stdout.print(
                "\n{s} - {s}\n{s}\n",
                .{ item.repository.full_name, item.path, item.html_url },
            );
        }
        for (item.text_matches) |match| {
            var it = std.mem.split(u8, match.fragment, "\n");
            while (it.next()) |line| {
                try stdout.print("  {s}\n", .{line});
            }
        }
    }
}
pub fn viewMarkdown(self: *Result) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print(
        \\# Query
        \\
        \\url: {s}
        \\total items: {d}
        \\
    , .{ self.url, self.result.total_count });

    for (self.result.items) |item| {
        try stdout.print(
            \\
            \\# `{s}`
            \\## [`{s}`]({s})
            \\
        , .{ item.repository.full_name, item.path, item.html_url });

        var it = std.mem.splitBackwards(u8, item.path, ".");
        const ext = it.first();
        for (item.text_matches) |match| {
            try stdout.print(
                "\n```{s}\n{s}\n```\n",
                .{ ext, match.fragment },
            );
        }
    }
}
