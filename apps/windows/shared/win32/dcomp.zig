//! DirectComposition, which mingw's dcomp.h only declares for C++. Only the
//! three interfaces the window uses, with the vtable slots counted from
//! that header (QueryInterface, AddRef and Release are 0 to 2; overloads
//! sit in MSVC order, the reverse of their declaration).

const c = @import("sdk");

const Unknown = extern struct {
    QueryInterface: *const anyopaque,
    AddRef: *const anyopaque,
    Release: *const fn (*anyopaque) callconv(.winapi) c.ULONG,
};

pub const Device = extern struct {
    lpVtbl: *const extern struct {
        unknown: Unknown,
        Commit: *const fn (*Device) callconv(.winapi) c.HRESULT,
        WaitForCommitCompletion: *const anyopaque,
        GetFrameStatistics: *const anyopaque,
        CreateTargetForHwnd: *const fn (*Device, c.HWND, c.BOOL, *?*Target) callconv(.winapi) c.HRESULT,
        CreateVisual: *const fn (*Device, *?*Visual) callconv(.winapi) c.HRESULT,
    },

    pub fn commit(self: *Device) c.HRESULT {
        return self.lpVtbl.Commit(self);
    }
    pub fn createTargetForHwnd(self: *Device, hwnd: c.HWND, topmost: bool, out: *?*Target) c.HRESULT {
        return self.lpVtbl.CreateTargetForHwnd(self, hwnd, @intFromBool(topmost), out);
    }
    pub fn createVisual(self: *Device, out: *?*Visual) c.HRESULT {
        return self.lpVtbl.CreateVisual(self, out);
    }
    pub fn release(self: *Device) void {
        _ = self.lpVtbl.unknown.Release(self);
    }
};

pub const Target = extern struct {
    lpVtbl: *const extern struct {
        unknown: Unknown,
        SetRoot: *const fn (*Target, ?*Visual) callconv(.winapi) c.HRESULT,
    },

    pub fn setRoot(self: *Target, visual: ?*Visual) c.HRESULT {
        return self.lpVtbl.SetRoot(self, visual);
    }
    pub fn release(self: *Target) void {
        _ = self.lpVtbl.unknown.Release(self);
    }
};

pub const Visual = extern struct {
    lpVtbl: *const extern struct {
        unknown: Unknown,
        /// SetOffsetX x2, SetOffsetY x2, SetTransform x2, SetTransformParent,
        /// SetEffect, SetBitmapInterpolationMode, SetBorderMode, SetClip x2.
        skipped: [12]*const anyopaque,
        SetContent: *const fn (*Visual, ?*anyopaque) callconv(.winapi) c.HRESULT,
    },

    pub fn setContent(self: *Visual, content: ?*anyopaque) c.HRESULT {
        return self.lpVtbl.SetContent(self, content);
    }
    pub fn release(self: *Visual) void {
        _ = self.lpVtbl.unknown.Release(self);
    }
};

pub extern "dcomp" fn DCompositionCreateDevice(dxgi_device: ?*anyopaque, iid: *const c.GUID, device: *?*anyopaque) callconv(.winapi) c.HRESULT;

test {
    @import("std").testing.refAllDecls(@This());
}
