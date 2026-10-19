//! The order of names in the tree: case does not matter and numbers compare
//! by value, so file2 comes before file10 (docs/spec/explorer.md).

const std = @import("std");

pub fn order(a: []const u8, b: []const u8) std.math.Order {
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len and j < b.len) {
        if (std.ascii.isDigit(a[i]) and std.ascii.isDigit(b[j])) {
            const end_a = digitsEnd(a, i);
            const end_b = digitsEnd(b, j);
            const numbers = numberOrder(a[i..end_a], b[j..end_b]);
            if (numbers != .eq) return numbers;
            i = end_a;
            j = end_b;
            continue;
        }
        const ca = std.ascii.toLower(a[i]);
        const cb = std.ascii.toLower(b[j]);
        if (ca != cb) return std.math.order(ca, cb);
        i += 1;
        j += 1;
    }
    const rest = std.math.order(a.len - i, b.len - j);
    if (rest != .eq) return rest;
    // Same ignoring case and leading zeros: keep a fixed order anyway.
    return std.mem.order(u8, a, b);
}

pub fn lessThan(a: []const u8, b: []const u8) bool {
    return order(a, b) == .lt;
}

fn digitsEnd(text: []const u8, start: usize) usize {
    var end = start;
    while (end < text.len and std.ascii.isDigit(text[end])) end += 1;
    return end;
}

/// Digit runs by value, any length: fewer significant digits is smaller.
fn numberOrder(a: []const u8, b: []const u8) std.math.Order {
    const x = std.mem.trimStart(u8, a, "0");
    const y = std.mem.trimStart(u8, b, "0");
    const by_length = std.math.order(x.len, y.len);
    if (by_length != .eq) return by_length;
    return std.mem.order(u8, x, y);
}

const testing = std.testing;

test "numbers by value, case ignored" {
    try testing.expect(lessThan("file2", "file10"));
    try testing.expect(lessThan("Apple", "banana"));
    try testing.expect(lessThan("apple", "Banana"));
    try testing.expect(lessThan("a", "ab"));
    try testing.expect(lessThan("v1.9", "v1.10"));
    try testing.expect(lessThan("99999999999999999999", "100000000000000000000"));
    try testing.expectEqual(std.math.Order.eq, order("same", "same"));
}
