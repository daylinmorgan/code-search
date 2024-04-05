const std = @import("std");
const Search = @import("search/Search.zig");
const Cli = @import("Cli.zig");
// const args = @import("zig-args");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli = try Cli.parse(allocator);
    const options = cli.options.options;
    defer cli.deinit();

    var search = Search.init(allocator);
    const query_str = try std.mem.join(allocator, " ", cli.options.positionals);
    defer allocator.free(query_str);

    var result = try search.fetch(&query_str, &options);
    defer result.deinit();
    try result.view(cli.options.options.format.?);
}
