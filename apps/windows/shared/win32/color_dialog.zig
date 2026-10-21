//! Windows' color dialog (ChooseColorW, comdlg32), for the accent color
//! (plan 15). Declared here because commdlg.h does not translate in C mode
//! with CINTERFACE (its print dialog interfaces fail, 2026-10-20).

const std = @import("std");
const c = @import("sdk");

const CHOOSECOLORW = extern struct {
    lStructSize: c.DWORD,
    hwndOwner: c.HWND,
    hInstance: ?*anyopaque = null,
    rgbResult: c.COLORREF,
    lpCustColors: [*]c.COLORREF,
    Flags: c.DWORD,
    lCustData: c.LPARAM = 0,
    lpfnHook: ?*const anyopaque = null,
    lpTemplateName: ?[*:0]const u16 = null,
};

const CC_RGBINIT: c.DWORD = 0x1;
const CC_FULLOPEN: c.DWORD = 0x2;

extern "comdlg32" fn ChooseColorW(chooser: *CHOOSECOLORW) callconv(.winapi) c.BOOL;

/// The custom colors the dialog keeps while the app runs.
var custom: [16]c.COLORREF = @splat(0xffffff);

/// Asks for a color, starting at `initial` (0xRRGGBB); the pick, or null
/// when cancelled.
pub fn pick(owner: c.HWND, initial: u32) ?u32 {
    var chooser: CHOOSECOLORW = .{
        .lStructSize = @sizeOf(CHOOSECOLORW),
        .hwndOwner = owner,
        .rgbResult = colorref(initial),
        .lpCustColors = &custom,
        .Flags = CC_RGBINIT | CC_FULLOPEN,
    };
    if (ChooseColorW(&chooser) == 0) return null;
    return colorref(@intCast(chooser.rgbResult));
}

/// COLORREF is 0x00BBGGRR: red and blue swap, both ways.
pub fn colorref(rgb: u32) u32 {
    return ((rgb & 0xff) << 16) | (rgb & 0xff00) | ((rgb >> 16) & 0xff);
}

test "red and blue swap, both ways" {
    try std.testing.expectEqual(@as(u32, 0x00332211), colorref(0x112233));
    try std.testing.expectEqual(@as(u32, 0x112233), colorref(0x00332211));
}
