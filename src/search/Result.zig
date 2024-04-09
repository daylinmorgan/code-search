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

pub const ViewFormat = enum { markdown, plain, glow, neovim };

pub fn view(self: *Result, format: ViewFormat) !void {
    switch (format) {
        .markdown => {
            const stdout = std.io.getStdOut();
            try self.viewMarkdown(stdout);
        },
        .plain => try self.viewPlain(),
        .glow, .neovim => |f| try self.viewChild(f),
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
pub fn viewMarkdown(self: *Result, stdout: std.fs.File) !void {
    const writer = stdout.writer();

    try writer.print(
        \\# Query
        \\
        \\url: {s}
        \\total items: {d}
        \\
    , .{ self.url, self.result.total_count });

    for (self.result.items) |item| {
        try writer.print(
            \\
            \\# `{s}`
            \\## [`{s}`]({s})
            \\
        , .{ item.repository.full_name, item.path, item.html_url });

        var it = std.mem.splitBackwards(u8, item.path, ".");
        const ext = it.first();
        for (item.text_matches) |match| {
            try writer.print(
                "\n```{s}\n{s}\n```\n",
                .{ ext, match.fragment },
            );
        }
    }
}

/// Determine the terminal window width in columns
/// modified from PR to std.Progress
fn determineTerminalWidth() ?usize {
    // if (self.terminal == null) return null;
    const terminal = std.io.getStdErr();
    const windows = std.os.windows;
    const builtin = @import("builtin");
    switch (builtin.os.tag) {
        .linux => {
            var window_size: std.os.linux.winsize = undefined;
            const exit_code = std.os.linux.ioctl(terminal.handle, std.os.linux.T.IOCGWINSZ, @intFromPtr(&window_size));
            if (exit_code < 0) return null;
            return @intCast(window_size.ws_col);
        },
        .macos => {
            var window_size: std.c.winsize = undefined;
            const exit_code = std.c.ioctl(terminal.handle, std.c.T.IOCGWINSZ, @intFromPtr(&window_size));
            if (exit_code < 0) return null;
            return @intCast(window_size.ws_col);
        },
        .windows => {
            var screen_buffer_info: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
            const exit_code = windows.kernel32.GetConsoleScreenBufferInfo(terminal.handle, &screen_buffer_info);
            if (exit_code != windows.TRUE) return null;
            return @intCast(screen_buffer_info.dwSize.X - 1);
        },
        else => return null,
    }
    return null;
}

pub fn viewChild(self: *Result, format: ViewFormat) !void {
    const termWidth = try std.fmt.allocPrint(
        self.allocator,
        "{d}",
        .{determineTerminalWidth() orelse 100},
    );
    defer self.allocator.free(termWidth);

    var child = std.ChildProcess.init(
        switch (format) {
            .glow => &.{
                "glow",
                "-p",
                "-w",
                termWidth,
            },
            .neovim => &.{
                "nvim",
                "-c",
                "set filetype=markdown",
                "-R",
                "-",
            },
            else => unreachable,
        },
        self.allocator,
    );

    child.stdin_behavior = .Pipe;

    try child.spawn();
    try self.viewMarkdown(child.stdin.?);

    // Send EOF to stdin. copied from compiler...
    // stdin must be set to null for some reason
    child.stdin.?.close();
    child.stdin = null;

    // TODO: report exit status?
    _ = try child.wait();
}
