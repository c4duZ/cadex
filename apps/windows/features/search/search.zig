//! The search feature (docs/spec/search.md): two palette lists over the
//! workspace, through the core. Files by name (Ctrl+Shift+P, the Mac's ⌘P):
//! the core's index, 50 rows, the recent ones with the field empty, each row
//! the name with its folder in grey. Text in files (the Mac's ⌘⇧F): every
//! key cancels the core's search and starts another; batches come on the
//! core's thread into a locked list, and a generation number drops the
//! batches of an old search.

const std = @import("std");
const cadex = @import("cadex");
const icons = @import("icons");
const strings = @import("strings");
const palette = @import("command-palette");

pub const Host = struct {
    context: *anyopaque,
    /// Opens `path` (absolute) at `line` (0: none) as chosen in the list.
    open: *const fn (context: *anyopaque, path: []const u8, line: u32, how: palette.How) void,
    /// From the core's thread: wake the window (PostMessage).
    wake: *const fn (context: *anyopaque) void,
    /// The palette, to open the lists from the commands.
    show: *const fn (context: *anyopaque, source: palette.Source) void,
    /// Whether the text list is the one open (the toggles only work then).
    content_open: *const fn (context: *anyopaque) bool,
};

const Hit = struct { path: []u8, line: u32, text: []u8, match_start: u32, match_len: u32 };

pub const Search = struct {
    gpa: std.mem.Allocator,
    host: Host,
    root: ?[]u8 = null,
    show_hidden: bool = true,
    index: ?*cadex.cadex_search_index = null,
    recent: std.ArrayList([]u8) = .empty,
    case_sensitive: bool = false,
    regex: bool = false,
    running: ?*cadex.cadex_search_content = null,
    lock: std.atomic.Mutex = .unlocked,
    hits: std.ArrayList(Hit) = .empty,
    generation: u32 = 0,
    done: ?struct { truncated: bool, files: u32 } = null,
    failed: ?[]const u8 = null,
    last_query: std.ArrayList(u8) = .empty,
    /// Per-search contexts handed to the core: index = generation % len.
    tickets: [4]Ticket = undefined,

    const Ticket = struct { owner: *Search, generation: u32 };
    const max_recent = 10;
    const file_rows = 50;

    pub fn deinit(self: *Search) void {
        self.stopContent();
        if (self.index) |i| cadex.cadex_search_index_close(i);
        if (self.root) |r| self.gpa.free(r);
        for (self.recent.items) |r| self.gpa.free(r);
        self.recent.deinit(self.gpa);
        self.clearHits();
        self.hits.deinit(self.gpa);
        self.last_query.deinit(self.gpa);
    }

    /// The workspace changed (or "show hidden"): a new index; the same values do nothing.
    pub fn setRoot(self: *Search, root: []const u8, show_hidden: bool) void {
        if (self.root) |r| if (std.mem.eql(u8, r, root) and self.show_hidden == show_hidden) return;
        if (self.index) |i| cadex.cadex_search_index_close(i);
        self.index = null;
        if (self.root) |r| self.gpa.free(r);
        self.root = self.gpa.dupe(u8, root) catch null;
        self.show_hidden = show_hidden;
        const z = self.gpa.dupeZ(u8, root) catch return;
        defer self.gpa.free(z);
        var out: ?*cadex.cadex_search_index = null;
        if (cadex.cadex_search_index_open(z.ptr, show_hidden, &out) == cadex.CADEX_OK) self.index = out;
    }

    fn absolute(self: *Search, arena: std.mem.Allocator, rel: []const u8) []const u8 {
        const root = self.root orelse return rel;
        const joined = std.fmt.allocPrint(arena, "{s}\\{s}", .{ root, rel }) catch return rel;
        std.mem.replaceScalar(u8, joined, '/', '\\');
        return joined;
    }

    // ---- Files by name ----

    pub fn filesSource(self: *Search) palette.Source {
        return .{ .context = self, .placeholder = strings.t("Find file by name", "Buscar arquivo pelo nome"), .empty_text = strings.t("No files found", "Nenhum arquivo encontrado"), .icon = icons.phosphor.file, .opens_files = true, .search = searchFiles, .choose = chooseFile };
    }

    fn fileItem(arena: std.mem.Allocator, rel: []const u8, positions: []const u32) palette.Item {
        const cut = std.mem.lastIndexOfScalar(u8, rel, '/');
        const name = if (cut) |c| rel[c + 1 ..] else rel;
        const name_at: u32 = @intCast(rel.len - name.len);
        var bold: std.ArrayList(u32) = .empty;
        for (positions) |p| if (p >= name_at) bold.append(arena, p - name_at) catch {};
        return .{ .id = rel, .title = name, .detail = if (cut) |c| rel[0..c] else "", .icon = icons.forFileNamed(name), .icon_color = icons.colorForFileNamed(name), .file_name = name, .bold = bold.items };
    }

    fn searchFiles(context: *anyopaque, arena: std.mem.Allocator, query: []const u8, out: *std.ArrayList(palette.Item)) ?[]const u8 {
        const self: *Search = @ptrCast(@alignCast(context));
        if (query.len == 0) {
            for (self.recent.items) |r| out.append(arena, fileItem(arena, r, &.{})) catch {};
            return if (self.recent.items.len == 0) strings.t("Type to find files", "Digite para buscar arquivos") else strings.t("Recent", "Recentes");
        }
        const index = self.index orelse return strings.t("Open a folder", "Abra uma pasta");
        var result: cadex.cadex_search_files_result = undefined;
        if (cadex.cadex_search_files(index, query.ptr, query.len, file_rows, &result) == cadex.CADEX_OK) {
            defer cadex.cadex_search_files_result_free(&result);
            for (result.matches[0..result.count]) |m| {
                const rel = arena.dupe(u8, result.paths[m.path_offset..][0..m.path_len]) catch continue;
                const positions = arena.dupe(u32, result.positions[m.positions_offset..][0..m.positions_count]) catch continue;
                out.append(arena, fileItem(arena, rel, positions)) catch {};
            }
        }
        var ready = false;
        const count = cadex.cadex_search_index_count(index, &ready);
        if (ready) return null;
        return std.fmt.allocPrint(arena, "{s} {d}", .{ strings.t("Indexing…", "Indexando…"), count }) catch null;
    }

    fn chooseFile(context: *anyopaque, id: []const u8, how: palette.How) void {
        const self: *Search = @ptrCast(@alignCast(context));
        self.remember(id);
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        self.host.open(self.host.context, self.absolute(arena.allocator(), id), 0, how);
    }

    fn remember(self: *Search, rel: []const u8) void {
        for (self.recent.items, 0..) |r, i| if (std.mem.eql(u8, r, rel)) {
            self.gpa.free(self.recent.orderedRemove(i));
            break;
        };
        const copy = self.gpa.dupe(u8, rel) catch return;
        self.recent.insert(self.gpa, 0, copy) catch return self.gpa.free(copy);
        if (self.recent.items.len > max_recent) self.gpa.free(self.recent.pop().?);
    }

    // ---- Text in files ----

    pub fn contentSource(self: *Search) palette.Source {
        return .{ .context = self, .placeholder = strings.t("Find text in files", "Buscar texto nos arquivos"), .empty_text = strings.t("No results", "Nenhum resultado"), .icon = icons.phosphor.magnifying_glass, .opens_files = true, .search = searchContent, .choose = chooseHit, .reset = resetContent };
    }

    fn clearHits(self: *Search) void {
        for (self.hits.items) |h| {
            self.gpa.free(h.path);
            self.gpa.free(h.text);
        }
        self.hits.clearRetainingCapacity();
    }

    fn stopContent(self: *Search) void {
        if (self.running) |r| cadex.cadex_search_content_cancel(r);
        self.running = null;
    }

    fn resetContent(context: *anyopaque) void {
        const self: *Search = @ptrCast(@alignCast(context));
        self.stopContent();
        self.last_query.clearRetainingCapacity();
    }

    fn start(self: *Search, query: []const u8) void {
        self.stopContent();
        spin(&self.lock);
        self.generation +%= 1;
        self.clearHits();
        self.done = null;
        self.failed = null;
        self.lock.unlock();
        self.last_query.clearRetainingCapacity();
        self.last_query.appendSlice(self.gpa, query) catch {};
        if (query.len == 0) return;
        const root = self.root orelse return;
        const z = self.gpa.dupeZ(u8, root) catch return;
        defer self.gpa.free(z);
        const ticket = &self.tickets[self.generation % self.tickets.len];
        ticket.* = .{ .owner = self, .generation = self.generation };
        const options: cadex.cadex_search_content_options = .{ .case_sensitive = self.case_sensitive, .regex = self.regex, .show_hidden = self.show_hidden, .max_results = 0 };
        const callbacks: cadex.cadex_search_content_callbacks = .{ .context = ticket, .on_hits = onHits, .on_done = onDone };
        var out: ?*cadex.cadex_search_content = null;
        const started = cadex.cadex_search_content_start(z.ptr, query.ptr, query.len, &options, &callbacks, &out);
        if (started != cadex.CADEX_OK) {
            self.failed = if (started == cadex.CADEX_INVALID_ARGUMENT and self.regex) strings.t("Invalid regular expression", "Expressão regular inválida") else strings.t("The search failed", "A busca falhou");
            return;
        }
        self.running = out;
    }

    fn onHits(context: ?*anyopaque, hits: [*c]const cadex.cadex_search_hit, count: usize) callconv(.c) void {
        const ticket: *Ticket = @ptrCast(@alignCast(context.?));
        const self = ticket.owner;
        spin(&self.lock);
        defer self.lock.unlock();
        if (ticket.generation != self.generation) return;
        for (hits[0..count]) |h| {
            const path = self.gpa.dupe(u8, std.mem.span(h.path)) catch continue;
            const text = self.gpa.dupe(u8, h.text[0..h.text_len]) catch {
                self.gpa.free(path);
                continue;
            };
            self.hits.append(self.gpa, .{ .path = path, .line = h.line, .text = text, .match_start = h.match_start, .match_len = h.match_len }) catch {};
        }
        self.host.wake(self.host.context);
    }

    fn onDone(context: ?*anyopaque, truncated: bool, files: u32) callconv(.c) void {
        const ticket: *Ticket = @ptrCast(@alignCast(context.?));
        const self = ticket.owner;
        spin(&self.lock);
        defer self.lock.unlock();
        if (ticket.generation != self.generation) return;
        self.done = .{ .truncated = truncated, .files = files };
        self.host.wake(self.host.context);
    }

    fn searchContent(context: *anyopaque, arena: std.mem.Allocator, query: []const u8, out: *std.ArrayList(palette.Item)) ?[]const u8 {
        const self: *Search = @ptrCast(@alignCast(context));
        if (!std.mem.eql(u8, query, self.last_query.items)) self.start(query);
        spin(&self.lock);
        defer self.lock.unlock();
        for (self.hits.items, 0..) |h, i| {
            var bold: std.ArrayList(u32) = .empty;
            var b = h.match_start;
            while (b < h.match_start + h.match_len and b < h.text.len) : (b += 1) bold.append(arena, b) catch {};
            const name = std.fs.path.basenamePosix(h.path);
            out.append(arena, .{
                .id = std.fmt.allocPrint(arena, "{d}", .{i}) catch continue,
                .title = arena.dupe(u8, std.mem.trim(u8, h.text, " \t")) catch continue,
                .detail = std.fmt.allocPrint(arena, "{s}:{d}", .{ h.path, h.line }) catch "",
                .icon = icons.forFileNamed(name),
                .icon_color = icons.colorForFileNamed(name),
                .file_name = name,
                .bold = shiftBold(arena, h.text, bold.items),
            }) catch {};
        }
        return self.status(arena, query);
    }

    /// The bold offsets after the leading spaces the title drops.
    fn shiftBold(arena: std.mem.Allocator, text: []const u8, bold: []const u32) []const u32 {
        const lead: u32 = @intCast(text.len - std.mem.trimStart(u8, text, " \t").len);
        var out: std.ArrayList(u32) = .empty;
        for (bold) |b| if (b >= lead) out.append(arena, b - lead) catch {};
        return out.items;
    }

    /// "Aa .* · 12 resultados", the options in effect in front.
    fn status(self: *Search, arena: std.mem.Allocator, query: []const u8) ?[]const u8 {
        const opts = if (self.case_sensitive and self.regex) "Aa .* · " else if (self.case_sensitive) "Aa · " else if (self.regex) ".* · " else "";
        if (self.failed) |f| return std.fmt.allocPrint(arena, "{s}{s}", .{ opts, f }) catch f;
        if (query.len == 0) return if (opts.len > 0) opts[0 .. opts.len - 3] else null;
        if (self.done) |d| {
            if (d.truncated) return std.fmt.allocPrint(arena, "{s}{s}", .{ opts, strings.t("Too many results, refine the search", "Resultados demais, refine a busca") }) catch null;
            return std.fmt.allocPrint(arena, "{s}{d} {s} {d} {s}", .{ opts, self.hits.items.len, strings.t("results in", "resultados em"), d.files, strings.t("files", "arquivos") }) catch null;
        }
        if (self.hits.items.len == 0) return std.fmt.allocPrint(arena, "{s}{s}", .{ opts, strings.t("Searching…", "Buscando…") }) catch null;
        return std.fmt.allocPrint(arena, "{s}{d} {s}", .{ opts, self.hits.items.len, strings.t("results", "resultados") }) catch null;
    }

    fn chooseHit(context: *anyopaque, id: []const u8, how: palette.How) void {
        const self: *Search = @ptrCast(@alignCast(context));
        const i = std.fmt.parseInt(usize, id, 10) catch return;
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        spin(&self.lock);
        if (i >= self.hits.items.len) {
            self.lock.unlock();
            return;
        }
        const h = self.hits.items[i];
        const path = self.absolute(arena.allocator(), h.path);
        const line = h.line;
        self.lock.unlock();
        self.host.open(self.host.context, path, line, how);
    }

    // ---- Commands ----

    pub fn register(self: *Search, registry: *palette.Registry) void {
        target = self;
        registry.add(.{ .id = "search.files", .title = strings.t("Find File by Name", "Buscar arquivo pelo nome"), .keywords = &.{ "go to file", "abrir", "quick open", "find file" }, .shortcut = "cmd+p", .run = openFiles });
        registry.add(.{ .id = "search.content", .title = strings.t("Find Text in Files", "Buscar texto nos arquivos"), .keywords = &.{ "find in files", "grep", "procurar" }, .shortcut = "cmd+shift+f", .run = openContent });
        registry.add(.{ .id = "search.toggle-case", .title = strings.t("Match Case in Text Search", "Diferenciar maiúsculas na busca de texto"), .keywords = &.{ "case", "caixa", "match case" }, .shortcut = "cmd+opt+c", .run = toggleCase, .available = contentOpen });
        registry.add(.{ .id = "search.toggle-regex", .title = strings.t("Use Regular Expression in Text Search", "Usar expressão regular na busca de texto"), .keywords = &.{ "regex", "regular" }, .shortcut = "cmd+opt+r", .run = toggleRegex, .available = contentOpen });
    }
};

var target: *Search = undefined;

fn openFiles(_: ?*anyopaque) void {
    target.host.show(target.host.context, target.filesSource());
}
fn openContent(_: ?*anyopaque) void {
    target.host.show(target.host.context, target.contentSource());
}
fn contentOpen(_: ?*anyopaque) bool {
    return target.host.content_open(target.host.context);
}
fn toggleCase(_: ?*anyopaque) void {
    target.case_sensitive = !target.case_sensitive;
    target.last_query.clearRetainingCapacity();
}
fn toggleRegex(_: ?*anyopaque) void {
    target.regex = !target.regex;
    target.last_query.clearRetainingCapacity();
}

fn spin(m: *std.atomic.Mutex) void {
    while (!m.tryLock()) std.atomic.spinLoopHint();
}

test {
    @import("win32").refAllDeep(@This());
}
