//! The Markdown index on a sample folder: links to files and headings,
//! wiki links, broken links, who points here, and following the disk.

const std = @import("std");
const testing = std.testing;
const workspace = @import("../workspace/workspace.zig");
const Index = @import("index.zig").Index;
const queries = @import("queries.zig");
const TestDir = @import("../../shared/test_dir.zig").TestDir;

extern "c" fn usleep(microseconds: c_uint) c_int;

fn waitReady(index: *Index, notes: usize) !void {
    var attempts: u32 = 0;
    while (attempts < 250) : (attempts += 1) {
        index.lock();
        const n = index.notes.count();
        index.unlock();
        if (index.ready.load(.acquire) and n == notes) return;
        _ = usleep(20 * 1000);
    }
    return error.IndexNeverReady;
}

test "links to files, headings and notes; broken ones; who points here" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("docs/spec");
    try dir.writeFile("README.md", "# Cadex\n\nVeja [busca](docs/spec/search.md#critérios-de-aceite) e [[Ideias]].\n");
    try dir.writeFile("docs/spec/search.md", "# search\n\n## Critérios de aceite\n\nVolta ao [início](../../README.md).\n");
    try dir.writeFile("docs/Ideias.md", "# Ideias\n\nNada [quebrado](falta.md) e [título](search.md#nada).\n");
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());
    const index = try Index.open(testing.allocator, &registry, dir.path());
    defer index.close();
    try waitReady(index, 3);

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const readme = try queries.checkLinks(a, index, "README.md", "# Cadex\n\nVeja [busca](docs/spec/search.md#critérios-de-aceite) e [[Ideias]] e [x](nada.md).\n");
    try testing.expectEqual(@as(usize, 3), readme.len);
    try testing.expectEqualStrings("docs/spec/search.md", readme[0].rel);
    try testing.expect(!readme[0].broken);
    try testing.expectEqual(@as(?u32, 2), readme[0].row);
    try testing.expectEqualStrings("docs/Ideias.md", readme[1].rel);
    try testing.expect(readme[2].broken);

    const ideias = try queries.checkLinks(a, index, "docs/Ideias.md", "[quebrado](falta.md) e [título](spec/search.md#nada)");
    try testing.expect(ideias[0].broken);
    try testing.expect(ideias[1].broken);

    const back = try queries.backlinks(a, index, "README.md");
    try testing.expectEqual(@as(usize, 1), back.len);
    try testing.expectEqualStrings("docs/spec/search.md", back[0].from);
    try testing.expectEqual(@as(u32, 4), back[0].row);
    const to_search = try queries.backlinks(a, index, "docs/spec/search.md");
    try testing.expectEqual(@as(usize, 1), to_search.len);

    const wiki = try queries.resolveDestination(a, index, "README.md", "ideias", true);
    try testing.expectEqualStrings("docs/Ideias.md", wiki.rel);
}

test "a new note on disk joins the index" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.writeFile("a.md", "# A\n");
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());
    const index = try Index.open(testing.allocator, &registry, dir.path());
    defer index.close();
    try waitReady(index, 1);
    _ = usleep(200 * 1000);
    try dir.makeDir("notes");
    try dir.writeFile("notes/b.md", "# B\n\n[a](../a.md)\n");
    try waitReady(index, 2);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const back = try queries.backlinks(arena.allocator(), index, "a.md");
    try testing.expectEqual(@as(usize, 1), back.len);
}
