const std = @import("std");
const gpa = std.heap.c_allocator;

const known_folders = @import("known-folders");
const u = @import("./util/index.zig");

//
//

pub fn execute(args: [][]u8) !void {
    //
    const home = try known_folders.getPath(gpa, .home);
    const dir = try std.fmt.allocPrint(gpa, "{}{}", .{home, "/.cache/zigmod/deps"});

    try fetch_deps(dir, "./zig.mod");

    //
    const f = try std.fs.cwd().createFile("./deps.zig", .{});
    defer f.close();

    const w = f.writer();
    try w.print("const std = @import(\"std\");\n", .{});
    try w.print("const Pkg = std.build.Pkg;\n", .{});
    try w.print("\n", .{});
    try w.print("const home = \"{}\";\n", .{home});
    try w.print("const cache = home ++ \"/.cache/zigmod/deps\";\n", .{});
    try w.print("\n", .{});
    try w.print("pub const packages = ", .{});
    try print_deps(w, dir, try u.ModFile.init(gpa, "./zig.mod"), 0);
    try w.print(";\n", .{});
}

fn fetch_deps(dir: []const u8, mpath: []const u8) anyerror!void {
    const m = try u.ModFile.init(gpa, mpath);
    for (m.deps) |d| {
        const p = try std.fmt.allocPrint(gpa, "{}{}{}", .{dir, "/", try d.clean_path()});
        switch (d.type) {
            .git => {
                u.print("fetch: {}: {}: {}", .{m.name, @tagName(d.type), d.path});
                if (!try u.does_file_exist(p)) {
                    try run_cmd(null, &[_][]const u8{"git", "clone", d.path, p});
                }
                else {
                    try run_cmd(p, &[_][]const u8{"git", "fetch"});
                    try run_cmd(p, &[_][]const u8{"git", "pull"});
                }
            },
        }
        switch (d.type) {
            else => {
                try fetch_deps(dir, try std.fmt.allocPrint(gpa, "{}{}", .{p, "/zig.mod"}));
            },
        }
    }
}

fn run_cmd(dir: ?[]const u8, args: []const []const u8) !void {
    _ = std.ChildProcess.exec(.{ .allocator = gpa, .cwd = dir, .argv = args, }) catch |e| switch(e) {
        error.FileNotFound => {
            u.assert(false, "\"{}\" command not found", .{args[0]});
        },
        else => return e,
    };
}

fn print_deps(w: std.fs.File.Writer, dir: []const u8, m: u.ModFile, tabs: i32) anyerror!void {
    if (m.deps.len == 0) {
        try w.print("null", .{});
        return;
    }
    try u.print_all(w, .{"&[_]Pkg{"}, true);
    const t = "    ";
    const r = try u.repeat(t, tabs);
    for (m.deps) |d| {
        const dcpath = try d.clean_path();
        const p = try u.concat(&[_][]const u8{dir, "/", dcpath});
        const np = try u.concat(&[_][]const u8{p, "/zig.mod"});
        const n = try u.ModFile.init(gpa, np);

        try w.print("{}\n", .{try u.concat(&[_][]const u8{r,t,"Pkg{"})});
        try w.print("{}\n", .{try u.concat(&[_][]const u8{r,t,t,".name = \"",n.name,"\","})});
        try w.print("{}\n", .{try u.concat(&[_][]const u8{r,t,t,".path = cache ++ \"/",dcpath,"/",n.main,"\","})});
        try w.print("{}", .{try u.concat(&[_][]const u8{r,t,t,".dependencies = "})});
        try print_deps(w, dir, n, tabs+2);
        try w.print("{}\n", .{","});
        try w.print("{}\n", .{try u.concat(&[_][]const u8{r,t,"},"})});
    }
    try w.print("{}", .{try u.concat(&[_][]const u8{r,"}"})});
}