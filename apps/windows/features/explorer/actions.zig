//! What each explorer command does, through the core's checked file
//! operations; the Recycle Bin is the system's (SHFileOperationW with undo),
//! with the item's folder checked in the workspace first.

const std = @import("std");
const w = @import("win32");
const ui = @import("ui");
const cadex = @import("cadex");
const explorer = @import("explorer.zig");

const Explorer = explorer.Explorer;
const c = w.c;

/// The folder new items go in: the selected folder, the selected file's
/// folder, or the root.
fn targetFolder(self: *Explorer) ?[]const u8 {
    if (self.selectedNode()) |n| {
        if (n.isFolder()) return n.path;
        return std.fs.path.dirnameWindows(n.path) orelse self.root();
    }
    return self.root();
}

/// "sem título", "sem título 2", ... free in `folder`; created, then renamed in place.
pub fn create(self: *Explorer, folder_kind: bool) void {
    const folder = targetFolder(self) orelse return;
    const base = if (folder_kind) "pasta sem título" else "sem título";
    var n: usize = 1;
    while (n < 1000) : (n += 1) {
        var buf: [1024]u8 = undefined;
        const name = if (n == 1) base else std.fmt.bufPrint(&buf, "{s} {d}", .{ base, n }) catch return;
        const path = std.fmt.allocPrintSentinel(self.gpa, "{s}\\{s}", .{ folder, name }, 0) catch return;
        defer self.gpa.free(path);
        const status = if (folder_kind) cadex.cadex_explorer_create_directory(path.ptr) else cadex.cadex_explorer_create_file(path.ptr);
        if (status == cadex.CADEX_ALREADY_EXISTS) continue;
        if (status != cadex.CADEX_OK) return self.say("Não foi possível criar aqui");
        if (self.tree) |*t| {
            if (t.find(folder)) |node| {
                if (!node.expanded) t.toggle(node) else t.load(node);
            }
        }
        self.select(path, false);
        beginRename(self);
        return;
    }
}

pub fn beginRename(self: *Explorer) void {
    const node = self.selectedNode() orelse return;
    if (self.renaming) |r| self.gpa.free(r);
    self.renaming = self.gpa.dupe(u8, node.path) catch null;
    self.rename_text.set(self.gpa, node.name) catch {};
    // The name without its extension is selected, as Windows Explorer does.
    const dot = std.mem.lastIndexOfScalar(u8, node.name, '.');
    self.rename_text.anchor = 0;
    self.rename_text.caret = if (dot) |d| (if (d > 0 and !node.isFolder()) d else node.name.len) else node.name.len;
}

/// Why `name` would be refused as the new name of `path`, or null.
pub fn renameProblem(self: *Explorer, path: []const u8, name: []const u8) ?[]const u8 {
    if (name.len == 0) return "O nome não pode ficar vazio";
    if (std.mem.indexOfAny(u8, name, "\\/:*?\"<>|") != null) return "O nome não pode ter \\ / : * ? \" < > |";
    const t = &(self.tree orelse return null);
    const parent_path = std.fs.path.dirnameWindows(path) orelse return null;
    const parent = t.find(parent_path) orelse return null;
    for (parent.children.items) |sibling| {
        if (std.mem.eql(u8, sibling.path, path)) continue;
        // NTFS ignores case: README and readme are the same name.
        if (std.ascii.eqlIgnoreCase(sibling.name, name)) return "Já existe um item com esse nome";
    }
    return null;
}

pub fn finishRename(self: *Explorer) void {
    const path = self.renaming orelse return;
    defer {
        self.gpa.free(path);
        self.renaming = null;
    }
    const name = std.mem.trim(u8, self.rename_text.text(), " ");
    if (std.mem.eql(u8, name, std.fs.path.basenameWindows(path))) return;
    if (renameProblem(self, path, name)) |problem| return self.say(problem);
    const from = self.gpa.dupeZ(u8, path) catch return;
    defer self.gpa.free(from);
    const to = self.gpa.dupeZ(u8, name) catch return;
    defer self.gpa.free(to);
    var out: [*c]u8 = null;
    var len: usize = 0;
    if (cadex.cadex_explorer_rename(from.ptr, to.ptr, &out, &len) != cadex.CADEX_OK) return self.say("Não foi possível renomear");
    defer cadex.cadex_free(out);
    reloadParent(self, path);
    self.select(out[0..len], false);
}

fn reloadParent(self: *Explorer, path: []const u8) void {
    const t = &(self.tree orelse return);
    const parent = std.fs.path.dirnameWindows(path) orelse return;
    if (t.find(parent)) |node| t.load(node);
}

/// Moves the selected items to the Recycle Bin; more than one asks first
/// (the caller asks; this does it).
pub fn trash(self: *Explorer) void {
    var list: std.ArrayList(u16) = .empty;
    defer list.deinit(self.gpa);
    for (self.selection.items) |p| {
        const z = self.gpa.dupeZ(u8, p) catch continue;
        defer self.gpa.free(z);
        if (!cadex.cadex_workspace_is_authorized(z.ptr)) continue;
        const wide = std.unicode.wtf8ToWtf16LeAlloc(self.gpa, p) catch continue;
        defer self.gpa.free(wide);
        list.appendSlice(self.gpa, wide) catch return;
        list.append(self.gpa, 0) catch return;
    }
    if (list.items.len == 0) return;
    // SHFileOperation takes a list ended by two NULs.
    list.append(self.gpa, 0) catch return;
    var op: c.SHFILEOPSTRUCTW = std.mem.zeroes(c.SHFILEOPSTRUCTW);
    op.wFunc = c.FO_DELETE;
    op.pFrom = @ptrCast(list.items.ptr);
    op.fFlags = c.FOF_ALLOWUNDO | c.FOF_NOCONFIRMATION | c.FOF_SILENT;
    if (c.SHFileOperationW(&op) != 0) self.say("Não foi possível mover para a Lixeira");
    for (self.selection.items) |p| reloadParent(self, p);
    self.clearSelection();
}

pub fn copyFiles(self: *Explorer) void {
    for (self.copied.items) |p| self.gpa.free(p);
    self.copied.clearRetainingCapacity();
    for (self.selection.items) |p| {
        const copy = self.gpa.dupe(u8, p) catch continue;
        self.copied.append(self.gpa, copy) catch self.gpa.free(copy);
    }
}

/// Copies what explorer.copy-files took into the target folder; next to a
/// namesake the copy is "x cópia.ext" (the core names it).
pub fn pasteFiles(self: *Explorer) void {
    const folder = targetFolder(self) orelse return;
    const dest = self.gpa.dupeZ(u8, folder) catch return;
    defer self.gpa.free(dest);
    for (self.copied.items) |p| {
        const from = self.gpa.dupeZ(u8, p) catch continue;
        defer self.gpa.free(from);
        var out: [*c]u8 = null;
        var len: usize = 0;
        if (cadex.cadex_explorer_copy(from.ptr, dest.ptr, &out, &len) != cadex.CADEX_OK) {
            self.say("Não foi possível colar");
            continue;
        }
        cadex.cadex_free(out);
    }
    if (self.tree) |*t| if (t.find(folder)) |n| t.load(n);
}

/// Drag and drop inside the tree: moves `paths` into `folder`.
pub fn move(self: *Explorer, paths: []const []const u8, folder: []const u8) void {
    const dest = self.gpa.dupeZ(u8, folder) catch return;
    defer self.gpa.free(dest);
    for (paths) |p| {
        const from = self.gpa.dupeZ(u8, p) catch continue;
        defer self.gpa.free(from);
        var out: [*c]u8 = null;
        var len: usize = 0;
        const status = cadex.cadex_explorer_move(from.ptr, dest.ptr, &out, &len);
        if (status != cadex.CADEX_OK) {
            self.say(if (status == cadex.CADEX_ALREADY_EXISTS) "Já existe um item com esse nome lá" else "Não foi possível mover");
            continue;
        }
        cadex.cadex_free(out);
        reloadParent(self, p);
    }
    if (self.tree) |*t| if (t.find(folder)) |n| t.load(n);
}

/// Shows the item selected in Windows Explorer.
pub fn reveal(self: *Explorer) void {
    const node = self.selectedNode() orelse return;
    const args = std.fmt.allocPrint(self.gpa, "/select,\"{s}\"", .{node.path}) catch return;
    defer self.gpa.free(args);
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(self.gpa, args) catch return;
    defer self.gpa.free(wide);
    _ = c.ShellExecuteW(null, w.L("open"), w.L("explorer.exe"), wide.ptr, null, c.SW_SHOWNORMAL);
}

pub fn copyPath(self: *Explorer, u: *ui.Ui, relative: bool) void {
    const node = self.selectedNode() orelse return;
    var text: []const u8 = node.path;
    if (relative) if (self.root()) |r| if (std.ascii.startsWithIgnoreCase(node.path, r) and node.path.len > r.len) {
        text = node.path[r.len + 1 ..];
    };
    ui.clipboard.writeText(self.gpa, u.hwnd, text);
}

/// "Abrir pasta…": the system's folder picker (IFileOpenDialog).
pub fn pickFolder(gpa: std.mem.Allocator, owner: c.HWND) ?[]u8 {
    const clsid = w.guid("dc1c5a9c-e88a-4dde-a5a1-60f82a20aef7"); // CLSID_FileOpenDialog
    const iid = w.guid("d57c7288-d4ad-4768-be02-9d969532d960"); // IID_IFileOpenDialog
    var raw: ?*anyopaque = null;
    if (c.CoCreateInstance(&clsid, null, c.CLSCTX_INPROC_SERVER, &iid, &raw) < 0) return null;
    const dialog: *c.IFileOpenDialog = @ptrCast(@alignCast(raw.?));
    defer w.release(dialog);
    var options: c.DWORD = 0;
    _ = w.call(dialog, "GetOptions", .{&options});
    _ = w.call(dialog, "SetOptions", .{options | c.FOS_PICKFOLDERS | c.FOS_FORCEFILESYSTEM});
    if (w.call(dialog, "Show", .{owner}) < 0) return null;
    var item: [*c]c.IShellItem = null;
    if (w.call(dialog, "GetResult", .{&item}) < 0) return null;
    defer w.release(item);
    var name: [*c]u16 = null;
    if (w.call(item, "GetDisplayName", .{ c.SIGDN_FILESYSPATH, &name }) < 0) return null;
    defer c.CoTaskMemFree(name);
    return std.unicode.wtf16LeToWtf8Alloc(gpa, std.mem.span(@as([*:0]u16, @ptrCast(name)))) catch null;
}

test {
    @import("win32").refAllDeep(@This());
}
