//! The Windows SDK for the app: `c` is sdk.h translated from the headers
//! Zig ships (docs/adr/0012-windows-zig-win32-d3d11.md), plus what those
//! headers cannot give: UTF-16 literals, COM calls, the interface ids the
//! missing libuuid would hold, and DirectComposition (C++ only in mingw).
//!
//! Avoid COM methods that return a struct by value (ID2D1RenderTarget's
//! GetSize, GetPixelFormat): their C declarations do not match the ABI the
//! system DLLs use.

const std = @import("std");

pub const c = @import("sdk");
pub const dcomp = @import("dcomp.zig");

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
    for (&data4, 0..) |*byte, i| byte.* = hex.parse(tail[i * 2 ..][0..2]);
    return .{
        .Data1 = hex.parse(text[0..8]),
        .Data2 = hex.parse(text[9..13]),
        .Data3 = hex.parse(text[14..18]),
        .Data4 = data4,
    };
}

/// The standard arrow; IDC_ARROW itself goes through a macro translate-c
/// cannot follow (MAKEINTRESOURCE).
pub const IDC_ARROW: [*:0]const u16 = @ptrFromInt(32512);
pub const IDC_IBEAM: [*:0]const u16 = @ptrFromInt(32513);
pub const IDC_SIZEWE: [*:0]const u16 = @ptrFromInt(32644);
pub const IDC_SIZENS: [*:0]const u16 = @ptrFromInt(32645);
pub const IDC_HAND: [*:0]const u16 = @ptrFromInt(32649);

pub const Error = error{ComFailed};

/// S_OK and the other success codes, or an error to log and give up on.
pub fn check(hr: HRESULT) Error!void {
    if (hr < 0) {
        std.log.warn("COM call failed: 0x{x}", .{@as(u32, @bitCast(hr))});
        return error.ComFailed;
    }
}

/// The return type of a COM method on `T` (a pointer to an interface).
fn MethodResult(comptime T: type, comptime method: []const u8) type {
    const Interface = @typeInfo(T).pointer.child;
    const Vtbl = @typeInfo(@FieldType(Interface, "lpVtbl")).pointer.child;
    const Fn = @typeInfo(@typeInfo(@FieldType(Vtbl, method)).optional.child).pointer.child;
    return @typeInfo(Fn).@"fn".return_type.?;
}

/// obj->lpVtbl->method(obj, args...) for the translated interfaces.
pub inline fn call(obj: anytype, comptime method: []const u8, args: anytype) MethodResult(@TypeOf(obj), method) {
    return @call(.auto, @field(obj.*.lpVtbl.*, method).?, .{obj} ++ args);
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

test "guids parse like the headers write them" {
    const g = guid("6f15aaf2-d208-4e89-9ab4-489535d34f9c");
    try std.testing.expectEqual(@as(c_ulong, 0x6f15aaf2), g.Data1);
    try std.testing.expectEqual(@as(u8, 0x9c), g.Data4[7]);
}
