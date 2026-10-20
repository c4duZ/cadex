//! WebView2's completion and event handlers are COM objects the app
//! implements: QueryInterface, AddRef, Release and Invoke. `Handler` makes
//! one from the translated vtable of the interface (so the signature of
//! Invoke is the header's) and a Zig function.
//!
//! The handler lives inside its owner (a View, the Environment) and counts
//! on the owner's references: WebView2 holds a handler until the event is
//! removed or the controller closed, and a creation callback can arrive
//! after the pane is gone, so the owner is freed only when the last
//! reference WebView2 holds is released, never under a pending callback.

const std = @import("std");
const w = @import("win32");
const c = w.c;

pub const iid_unknown = w.guid("00000000-0000-0000-c000-000000000046");
const E_NOINTERFACE: c.HRESULT = @bitCast(@as(u32, 0x80004002));

/// The Vtbl type behind interface `I` (its `lpVtbl` field).
fn VtblOf(comptime I: type) type {
    return @typeInfo(@FieldType(I, "lpVtbl")).pointer.child;
}

fn Param(comptime I: type, comptime index: usize) type {
    const F = @typeInfo(@FieldType(VtblOf(I), "Invoke")).optional.child;
    return @typeInfo(@typeInfo(F).pointer.child).@"fn".params[index].type.?;
}

/// A handler of interface `I` (id `iid`) embedded in `Owner` at field
/// `field`; `invoke(owner, a, b)` gets Invoke's two arguments (an HRESULT
/// and a result for completions, sender and args for events). `Owner` has
/// `retain()` and `release()`.
pub fn Handler(
    comptime I: type,
    comptime iid: *const c.GUID,
    comptime Owner: type,
    comptime field: []const u8,
    comptime invoke: fn (*Owner, Param(I, 1), Param(I, 2)) c.HRESULT,
) type {
    return extern struct {
        lpVtbl: *const VtblOf(I) = &vtbl,

        const Self = @This();

        const vtbl: VtblOf(I) = .{
            .QueryInterface = queryInterface,
            .AddRef = addRef,
            .Release = release,
            .Invoke = invokeThunk,
        };

        /// What WebView2's add_* and Create* calls take.
        pub fn ptr(self: *Self) *I {
            return @ptrCast(self);
        }

        fn owner(this: anytype) *Owner {
            const self: *Self = @ptrCast(@alignCast(this));
            return @alignCast(@fieldParentPtr(field, self));
        }

        fn queryInterface(this: Param(I, 0), riid: [*c]const c.IID, out: [*c]?*anyopaque) callconv(.c) c.HRESULT {
            const asked: *const c.GUID = @ptrCast(riid);
            if (sameGuid(asked, iid) or sameGuid(asked, &iid_unknown)) {
                out.* = @ptrCast(this);
                owner(this).retain();
                return 0;
            }
            out.* = null;
            return E_NOINTERFACE;
        }

        fn addRef(this: Param(I, 0)) callconv(.c) c.ULONG {
            owner(this).retain();
            return 2;
        }

        fn release(this: Param(I, 0)) callconv(.c) c.ULONG {
            owner(this).release();
            return 1;
        }

        fn invokeThunk(this: Param(I, 0), a: Param(I, 1), b: Param(I, 2)) callconv(.c) c.HRESULT {
            return invoke(owner(this), a, b);
        }
    };
}

/// The bytes of a GUID compared, for QueryInterface in the tests.
pub fn sameGuid(a: *const c.GUID, b: *const c.GUID) bool {
    return std.mem.eql(u8, std.mem.asBytes(a), std.mem.asBytes(b));
}

test "a handler counts on its owner and answers only its own id" {
    const iids = @import("sdk/iids.zig");
    const Owner = struct {
        refs: u32 = 1,
        calls: u32 = 0,
        handler: H = .{},

        const H = Handler(c.ICoreWebView2DocumentTitleChangedEventHandler, &iids.ICoreWebView2DocumentTitleChangedEventHandler, @This(), "handler", onTitle);

        fn onTitle(self: *@This(), _: [*c]c.ICoreWebView2, _: [*c]c.IUnknown) c.HRESULT {
            self.calls += 1;
            return 0;
        }
        fn retain(self: *@This()) void {
            self.refs += 1;
        }
        fn release(self: *@This()) void {
            self.refs -= 1;
        }
    };
    var o: Owner = .{};
    const h = o.handler.ptr();
    _ = h.lpVtbl.*.AddRef.?(h);
    try std.testing.expectEqual(@as(u32, 2), o.refs);
    _ = h.lpVtbl.*.Invoke.?(h, null, null);
    try std.testing.expectEqual(@as(u32, 1), o.calls);
    var out: ?*anyopaque = null;
    try std.testing.expect(h.lpVtbl.*.QueryInterface.?(h, &iids.ICoreWebView2, &out) < 0);
    try std.testing.expect(h.lpVtbl.*.QueryInterface.?(h, &iid_unknown, &out) == 0);
    _ = h.lpVtbl.*.Release.?(h);
    _ = h.lpVtbl.*.Release.?(h);
    try std.testing.expectEqual(@as(u32, 1), o.refs);
}

test {
    @import("win32").refAllDeep(@This());
}
