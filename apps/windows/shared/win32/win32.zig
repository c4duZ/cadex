//! The Windows SDK for the app: `c` is sdk.h translated from the headers
//! Zig ships (docs/adr/0012-windows-zig-win32-d3d11.md), plus what those
//! headers cannot give: UTF-16 literals, COM calls, the interface ids the
//! missing libuuid would hold, and DirectComposition (C++ only in mingw).
//!
//! sdk.h defines UNICODE, so a vtable field named like a GDI macro carries
//! the macro's W name (IDWriteFontFace's "GetGlyphIndicesW"); call errors
//! name the vtable to look in.
//!
//! Avoid COM methods that return a struct by value (ID2D1RenderTarget's
//! GetSize, GetPixelFormat): their C declarations do not match the ABI the
//! system DLLs use.

const std = @import("std");

pub const c = @import("sdk");
pub const dcomp = @import("dcomp.zig");
pub const files = @import("files.zig");

pub const HRESULT = c.HRESULT;
pub const HWND = c.HWND;

/// A UTF-16 literal for the W functions.
pub fn L(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}

/// An interface id written as in the headers: "db6f6ddb-ac77-4e88-8253-819df9bbf140".
pub fn guid(comptime text: []const u8) c.GUID {
    @setEvalBranchQuota(10_000);
    const hex = struct {
        fn parse(comptime s: []const u8) comptime_int {
            return std.fmt.parseInt(u64, s, 16) catch @compileError("bad guid " ++ text);
        }
    };
    var data4: [8]u8 = undefined;
    const tail = text[19..23] ++ text[24..36];
    inline for (0..8) |i| data4[i] = hex.parse(tail[i * 2 ..][0..2]);
    return .{
        .Data1 = hex.parse(text[0..8]),
        .Data2 = hex.parse(text[9..13]),
        .Data3 = hex.parse(text[14..18]),
        .Data4 = data4,
    };
}

/// The standard cursors by id (IDC_ARROW and the others go through
/// MAKEINTRESOURCE, which translate-c cannot follow, and their odd values
/// are no valid u16 pointer).
pub const Cursor = enum(usize) { arrow = 32512, ibeam = 32513, size_we = 32644, size_ns = 32645, hand = 32649 };

extern "user32" fn LoadCursorW(instance: ?*anyopaque, name: usize) callconv(.winapi) c.HCURSOR;

pub fn loadCursor(cursor: Cursor) c.HCURSOR {
    return LoadCursorW(null, @intFromEnum(cursor));
}

extern "user32" fn LoadIconW(instance: c.HINSTANCE, name: usize) callconv(.winapi) c.HICON;

/// The icon resource `id` of the exe (1: the app's, from packaging).
pub fn loadIcon(instance: c.HINSTANCE, id: usize) c.HICON {
    return LoadIconW(instance, id);
}

pub const Error = error{ComFailed};

/// S_OK and the other success codes, or an error to log and give up on.
pub fn check(hr: HRESULT) Error!void {
    if (hr < 0) {
        std.log.warn("COM call failed: 0x{x}", .{@as(u32, @bitCast(hr))});
        return error.ComFailed;
    }
}

/// The vtable field holding `method`, looked up through the `Base` chain
/// the headers use for inherited interfaces (all of D2D).
fn MethodPtr(comptime Vtbl: type, comptime method: []const u8) type {
    if (@hasField(Vtbl, method)) return @typeInfo(@FieldType(Vtbl, method)).optional.child;
    if (@hasField(Vtbl, "Base")) return MethodPtr(@FieldType(Vtbl, "Base"), method);
    @compileError("no COM method " ++ method ++ " on " ++ @typeName(Vtbl));
}

inline fn methodOf(vtbl: anytype, comptime method: []const u8) MethodPtr(@typeInfo(@TypeOf(vtbl)).pointer.child, method) {
    const Vtbl = @typeInfo(@TypeOf(vtbl)).pointer.child;
    if (@hasField(Vtbl, method)) return @field(vtbl.*, method).?;
    return methodOf(&vtbl.Base, method);
}

fn VtblOf(comptime T: type) type {
    const Interface = @typeInfo(T).pointer.child;
    return @typeInfo(@FieldType(Interface, "lpVtbl")).pointer.child;
}

fn MethodResult(comptime T: type, comptime method: []const u8) type {
    const Fn = @typeInfo(MethodPtr(VtblOf(T), method)).pointer.child;
    return @typeInfo(Fn).@"fn".return_type.?;
}

/// obj->lpVtbl->method(obj, args...) for the translated interfaces; an
/// inherited method gets `obj` as the base interface it expects.
pub inline fn call(obj: anytype, comptime method: []const u8, args: anytype) MethodResult(@TypeOf(obj), method) {
    // A single-item pointer: [*c] pointers have no field access.
    const vtbl: *const VtblOf(@TypeOf(obj)) = @ptrCast(obj.*.lpVtbl);
    const f = methodOf(vtbl, method);
    const Fn = @typeInfo(@TypeOf(f)).pointer.child;
    var full: std.meta.ArgsTuple(Fn) = undefined;
    full[0] = @ptrCast(obj);
    inline for (args, 1..) |arg, i| full[i] = coerce(@TypeOf(full[i]), arg);
    return @call(.auto, f, full);
}

/// The headers mix signed and unsigned for the same enums (a c_int
/// constant for a UINT parameter): integers are cast, the rest passes as is.
inline fn coerce(comptime T: type, arg: anytype) T {
    const A = @TypeOf(arg);
    if (@typeInfo(T) == .int and (@typeInfo(A) == .int or A == comptime_int)) return @intCast(arg);
    return arg;
}

/// Release on any interface pointer (optional too).
pub fn release(obj: anytype) void {
    const T = @TypeOf(obj);
    if (@typeInfo(T) == .optional) {
        if (obj) |o| _ = call(o, "Release", .{});
    } else {
        _ = call(obj, "Release", .{});
    }
}

/// QueryInterface into `Target`, given its id.
pub fn query(obj: anytype, comptime Target: type, id: *const c.GUID) Error!*Target {
    var out: ?*anyopaque = null;
    try check(call(obj, "QueryInterface", .{ id, &out }));
    return @ptrCast(@alignCast(out.?));
}

/// The ids the app asks for, from the headers' MIDL_INTERFACE / DEFINE_GUID.
pub const iid = struct {
    pub const ID3D11Texture2D = guid("6f15aaf2-d208-4e89-9ab4-489535d34f9c");
    pub const IDXGIDevice = guid("54ec77fa-1377-44e6-8c32-88fd5f44c84c");
    pub const IDXGIFactory2 = guid("50c83a1c-e072-4c48-87b0-3630fa36a6d0");
    pub const IDXGISurface = guid("cafcb56c-6ac3-4889-bf47-9e23bbd260ec");
    pub const ID2D1Factory1 = guid("bb12d362-daee-4b9a-aa1d-14ba401cfa1f");
    pub const IDWriteFactory5 = guid("958db99a-be2a-4f09-af7d-65189803d1d3");
    pub const IDCompositionDevice = guid("c37ea93a-e7aa-450d-b16f-9746cb0407f3");
};

pub const LOWORD = struct {
    pub fn of(value: anytype) u16 {
        return @truncate(@as(usize, @bitCast(value)));
    }
}.of;

pub fn HIWORD(value: anytype) u16 {
    return @truncate(@as(usize, @bitCast(value)) >> 16);
}

/// GET_X_LPARAM / GET_Y_LPARAM: signed, for multiple monitors.
pub fn xParam(lparam: c.LPARAM) i32 {
    return @as(i16, @bitCast(LOWORD(lparam)));
}

pub fn yParam(lparam: c.LPARAM) i32 {
    return @as(i16, @bitCast(HIWORD(lparam)));
}

/// For tests: references every public declaration of `T` and, inside the
/// app's own types, of their methods too, so building the test exe
/// type-checks code no test calls. std.testing.refAllDecls stops at the
/// top level (a method's body went unchecked until the exe was built,
/// 2026-10-20); refAllDeclsRecursive would walk into the whole SDK.
pub fn refAllDeep(comptime T: type) void {
    refDepth(T, 0);
}

fn refDepth(comptime T: type, comptime depth: u8) void {
    if (!@import("builtin").is_test) return;
    @setEvalBranchQuota(100_000);
    if (depth > 6) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
        const value = @field(T, decl.name);
        if (@TypeOf(value) == type) {
            if (comptime isOurs(value)) switch (@typeInfo(value)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refDepth(value, depth + 1),
                else => {},
            };
        } else {
            _ = &value;
        }
    }
}

fn isOurs(comptime T: type) bool {
    @setEvalBranchQuota(100_000);
    const name = @typeName(T);
    // The translated headers, the standard library, and the root of each.
    const foreign = [_][]const u8{ "sdk", "std", "cadex", "builtin", "debug" };
    for (foreign) |f| {
        if (std.mem.eql(u8, name, f)) return false;
        if (name.len > f.len and std.mem.startsWith(u8, name, f) and name[f.len] == '.') return false;
    }
    return true;
}

test "guids parse like the headers write them" {
    const g = guid("6f15aaf2-d208-4e89-9ab4-489535d34f9c");
    try std.testing.expectEqual(@as(c_ulong, 0x6f15aaf2), g.Data1);
    try std.testing.expectEqual(@as(u8, 0x9c), g.Data4[7]);
}

test {
    @import("win32.zig").refAllDeep(@This());
    _ = @import("dcomp.zig");
    _ = @import("files.zig");
}
