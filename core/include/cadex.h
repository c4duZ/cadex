/* Cadex core C API. The only door from the apps into the core (ADR 0002).
 *
 * Conventions:
 * - Functions are prefixed cadex_<feature>_.
 * - Every call that can fail returns a cadex_status; CADEX_OK is success.
 * - Whoever allocates frees: buffers returned by the core are released with
 *   cadex_free.
 */
#ifndef CADEX_H
#define CADEX_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Status (core/status.zig) ------------------------------------------ */

typedef int32_t cadex_status;

#define CADEX_OK 0
#define CADEX_INVALID_ARGUMENT 1
#define CADEX_OUT_OF_MEMORY 2
#define CADEX_SPAWN_FAILED 3
#define CADEX_IO_FAILED 4
#define CADEX_NOT_FOUND 5      /* the path does not exist */
#define CADEX_NOT_AUTHORIZED 6 /* outside every authorized directory */
#define CADEX_PERMISSION_DENIED 7
#define CADEX_ALREADY_EXISTS 8 /* the name is taken */
#define CADEX_TOO_LARGE 9      /* above the size limit asked for */
#define CADEX_BINARY 10        /* not a text file */
#define CADEX_GIT_MISSING 11   /* no working git on the PATH */

/* Releases a buffer returned by the core. NULL is accepted. */
void cadex_free(void *ptr);

/* ---- Terminal (core/features/terminal) --------------------------------- */

typedef struct cadex_terminal cadex_terminal;

typedef struct {
    uint16_t cols;
    uint16_t rows;
    /* Directory the shell starts in. NULL: the inherited directory. */
    const char *cwd;
    /* Shell to run. NULL or "": $SHELL, then /bin/zsh. */
    const char *shell;
    /* Passed back to the callbacks. */
    void *context;
    /* Called on the core's reader thread: new output, schedule a redraw.
     * Must return quickly and must not call cadex_terminal_close. */
    void (*on_output)(void *context);
    /* Called on the reader thread when the shell exits on its own, with the
     * exit code (128 + signal if killed). Must not call cadex_terminal_close. */
    void (*on_exit)(void *context, int32_t exit_code);
    /* Called on the reader thread when the title changes (OSC 0/2); read it
     * with cadex_terminal_copy_title. Same rules as on_output. */
    void (*on_title)(void *context);
    /* Called on the reader thread when the program rings the bell. */
    void (*on_bell)(void *context);
    /* Lines of history to keep (at most 100 000). 0: 10 000. */
    uint32_t history_lines;
    /* Called on the reader thread when a local server's address shows up in
     * the output (http://localhost:5173/), once per address per session;
     * url is valid during the call. NULL: no detection. */
    void (*on_local_url)(void *context, const char *url);
} cadex_terminal_options;

/* Starts a login shell on a new pty. */
cadex_status cadex_terminal_open(const cadex_terminal_options *options, cadex_terminal **out);

/* Ends the shell (SIGHUP, then SIGKILL after 200 ms) and frees the session.
 * No callback runs after this returns. NULL is accepted. */
void cadex_terminal_close(cadex_terminal *terminal);

/* Sends input to the shell: typed keys, pasted text. */
cadex_status cadex_terminal_write(cadex_terminal *terminal, const uint8_t *bytes, size_t len);

/* -- Keys (core/features/terminal/input.zig) -- */

/* Keys that are not text. CADEX_KEY_NONE: the event is text with Ctrl or
 * Alt (Ctrl+C, Meta+B). */
#define CADEX_KEY_NONE        0
#define CADEX_KEY_ENTER       1
#define CADEX_KEY_TAB         2
#define CADEX_KEY_BACKSPACE   3
#define CADEX_KEY_ESCAPE      4
#define CADEX_KEY_DELETE      5
#define CADEX_KEY_INSERT      6
#define CADEX_KEY_HOME        7
#define CADEX_KEY_END         8
#define CADEX_KEY_PAGE_UP     9
#define CADEX_KEY_PAGE_DOWN   10
#define CADEX_KEY_UP          11
#define CADEX_KEY_DOWN        12
#define CADEX_KEY_LEFT        13
#define CADEX_KEY_RIGHT       14
/* F1..F12 are CADEX_KEY_F1 + 0..11. */
#define CADEX_KEY_F1          15
#define CADEX_KEY_F12         26

#define CADEX_MOD_SHIFT (1u << 0)
#define CADEX_MOD_CTRL  (1u << 1)
/* Only when Option acts as Meta; otherwise Option composes text. */
#define CADEX_MOD_ALT   (1u << 2)
#define CADEX_MOD_SUPER (1u << 3)

/* Sends a key press, encoded for the program's current modes (application
 * cursor keys, modifiers, kitty keyboard protocol). text: what the key typed
 * with Shift but without Ctrl or Option ("A" for Ctrl+Shift+A), may be empty.
 * unshifted_codepoint: the key without Shift ('a'), or 0. */
cadex_status cadex_terminal_key(cadex_terminal *terminal, uint16_t key, uint8_t mods,
                                const uint8_t *text, size_t text_len,
                                uint32_t unshifted_codepoint);

/* New size in cells, plus the cell size in pixels (programs may ask for it). */
cadex_status cadex_terminal_resize(cadex_terminal *terminal, uint16_t cols, uint16_t rows,
                                   uint16_t cell_width_px, uint16_t cell_height_px);

/* True while a program other than the shell runs in the foreground. */
bool cadex_terminal_has_foreground_process(cadex_terminal *terminal);

/* The title the program set (OSC 0/2), not NUL-terminated. Free with
 * cadex_free. No title: *out is NULL and *out_len is 0. */
cadex_status cadex_terminal_copy_title(cadex_terminal *terminal, uint8_t **out, size_t *out_len);

/* The session's current directory: what the shell reported with OSC 7
 * (file://host/path decoded), or else the directory of the program in the
 * foreground. Not NUL-terminated; free with cadex_free. Unknown: *out NULL. */
cadex_status cadex_terminal_copy_working_directory(cadex_terminal *terminal, uint8_t **out, size_t *out_len);

/* The cursor's default shape (CADEX_CURSOR_BLOCK, _BAR, _UNDERLINE) and
 * blinking, from the user's preferences. A shape the program set (DECSCUSR)
 * stays until it resets it. */
cadex_status cadex_terminal_set_cursor(cadex_terminal *terminal, uint8_t shape, bool blink);

/* The theme's colors for a terminal, 0xRRGGBB. */
typedef struct {
    uint32_t background;
    uint32_t foreground;
    uint32_t cursor;
    uint32_t ansi[16]; /* 8 normal, then 8 bright */
} cadex_terminal_colors;

_Static_assert(sizeof(cadex_terminal_colors) == 76, "cadex_terminal_colors layout");

/* Sets the theme's colors as the terminal's defaults. What a program changed
 * with OSC 4/10/11 stays; programs asking for colors get these. */
cadex_status cadex_terminal_set_colors(cadex_terminal *terminal, const cadex_terminal_colors *colors);

/* -- Drawing (core/features/terminal/render.zig) -- */

#define CADEX_CELL_BOLD           (1u << 0)
#define CADEX_CELL_ITALIC         (1u << 1)
#define CADEX_CELL_FAINT          (1u << 2)
#define CADEX_CELL_STRIKETHROUGH  (1u << 3)
/* First half of a double-width character: draw it across two cells. */
#define CADEX_CELL_WIDE           (1u << 4)
/* Second half of a wide character: draw nothing. */
#define CADEX_CELL_SPACER         (1u << 5)
/* bg differs from the frame background; otherwise skip drawing it. */
#define CADEX_CELL_HAS_BACKGROUND (1u << 6)
/* Inside the text selection. */
#define CADEX_CELL_SELECTED       (1u << 7)
/* A match of the open search, and the current match. */
#define CADEX_CELL_MATCH          (1u << 11)
#define CADEX_CELL_MATCH_CURRENT  (1u << 12)
/* Underline kind: (flags >> CADEX_CELL_UNDERLINE_SHIFT) & 7.
 * 0 none, 1 single, 2 double, 3 curly, 4 dotted, 5 dashed. */
#define CADEX_CELL_UNDERLINE_SHIFT 8

typedef struct {
    uint32_t fg;          /* 0xRRGGBB, inverse already applied */
    uint32_t bg;          /* 0xRRGGBB */
    uint32_t text_offset; /* into cadex_terminal_frame.text */
    uint16_t text_len;    /* UTF-8 bytes; 0 for an empty cell */
    uint16_t flags;       /* CADEX_CELL_* */
} cadex_terminal_cell;

#define CADEX_CURSOR_BLOCK        0
#define CADEX_CURSOR_BAR          1
#define CADEX_CURSOR_UNDERLINE    2
#define CADEX_CURSOR_BLOCK_HOLLOW 3

typedef struct {
    const cadex_terminal_cell *cells; /* rows * cols, row by row */
    const uint8_t *text;              /* UTF-8 of every cell */
    uint32_t text_len;
    uint32_t background;              /* 0xRRGGBB */
    uint32_t foreground;              /* 0xRRGGBB */
    uint32_t cursor_color;            /* valid if has_cursor_color */
    uint16_t cols;
    uint16_t rows;
    uint16_t cursor_x;
    uint16_t cursor_y;
    uint8_t cursor_style;             /* CADEX_CURSOR_* */
    bool cursor_visible;
    bool cursor_blinking;
    bool has_cursor_color;
    /* Rows of history plus screen, and the first row shown. The view is at
     * the bottom when scroll_offset + rows == scroll_total. */
    uint32_t scroll_total;
    uint32_t scroll_offset;
} cadex_terminal_frame;

/* Layout shared with render.zig, which asserts the same sizes. */
_Static_assert(sizeof(cadex_terminal_cell) == 16, "cadex_terminal_cell layout");
_Static_assert(sizeof(cadex_terminal_frame) == 56, "cadex_terminal_frame layout");

/* Captures the screen for drawing. Call only from the thread that draws;
 * the frame stays valid until the next call or cadex_terminal_close. */
cadex_status cadex_terminal_update_frame(cadex_terminal *terminal, const cadex_terminal_frame **out);

/* Visible text, one line per row, not NUL-terminated. Free with cadex_free.
 * Empty screen: *out is NULL and *out_len is 0. */
cadex_status cadex_terminal_copy_text(cadex_terminal *terminal, uint8_t **out, size_t *out_len);

/* -- Scrolling and selection (core/features/terminal/c_api_view.zig) -- */

/* Moves the view through the history by rows; negative goes up. */
cadex_status cadex_terminal_scroll(cadex_terminal *terminal, int32_t rows);

#define CADEX_SCROLL_TOP    0
#define CADEX_SCROLL_BOTTOM 1
cadex_status cadex_terminal_scroll_to(cadex_terminal *terminal, uint8_t where);

/* Where the pointer is, for selection. */
typedef struct {
    double x;               /* pixels from the view's top-left, padding included */
    double y;
    uint16_t col;           /* viewport cell under the pointer, clamped to the grid */
    uint16_t row;
    uint16_t cell_width;    /* pixels */
    uint16_t padding_left;  /* pixels */
    uint32_t view_height;   /* pixels: dragging past it scrolls */
} cadex_terminal_pointer;

_Static_assert(sizeof(cadex_terminal_pointer) == 32, "cadex_terminal_pointer layout");

/* Mouse down. clicks: 1 by cell (a plain click clears the selection), 2 by
 * word, 3 by line. extend: Shift+click moves the far end of the selection. */
cadex_status cadex_terminal_select_press(cadex_terminal *terminal, const cadex_terminal_pointer *pointer,
                                         uint8_t clicks, bool extend);
/* Mouse dragged. *autoscroll: -1 up, 1 down, 0 none; while not 0 and the
 * button is down, call cadex_terminal_select_autoscroll on a timer. */
cadex_status cadex_terminal_select_drag(cadex_terminal *terminal, const cadex_terminal_pointer *pointer,
                                        int8_t *autoscroll);
/* One timer step: scrolls a row and extends the selection. */
cadex_status cadex_terminal_select_autoscroll(cadex_terminal *terminal, const cadex_terminal_pointer *pointer,
                                              int8_t *autoscroll);
cadex_status cadex_terminal_select_release(cadex_terminal *terminal, const cadex_terminal_pointer *pointer);
/* Everything, history included. */
cadex_status cadex_terminal_select_all(cadex_terminal *terminal);
void cadex_terminal_select_clear(cadex_terminal *terminal);
bool cadex_terminal_has_selection(cadex_terminal *terminal);

/* The selected text, not NUL-terminated: lines wrapped by width come back
 * joined, trailing spaces trimmed. Free with cadex_free. No selection:
 * *out is NULL and *out_len is 0. Typing or writing to the terminal clears
 * the selection and scrolls to the bottom. */
cadex_status cadex_terminal_copy_selection(cadex_terminal *terminal, uint8_t **out, size_t *out_len);

/* -- Find (core/features/terminal/search.zig) -- */

/* Starts finding text in the screen and the history (ASCII letters ignore
 * case), replacing any search. len 0 stops it. Matches are marked in the
 * frame with CADEX_CELL_MATCH and CADEX_CELL_MATCH_CURRENT. */
cadex_status cadex_terminal_search_start(cadex_terminal *terminal, const uint8_t *needle, size_t len);
void cadex_terminal_search_stop(cadex_terminal *terminal);

#define CADEX_SEARCH_NEXT     0  /* toward older matches (Enter) */
#define CADEX_SEARCH_PREVIOUS 1  /* toward newer matches (Shift+Enter) */
/* Moves the current match, wrapping, and scrolls to it. *found: false when
 * there are no matches. */
cadex_status cadex_terminal_search_select(cadex_terminal *terminal, uint8_t direction, bool *found);
/* Matches found and the current one counting from 1 (0: none), for "3 de 12". */
cadex_status cadex_terminal_search_counts(cadex_terminal *terminal, uint32_t *total, uint32_t *current);

/* -- Links (core/features/terminal/links.zig) -- */

#define CADEX_LINK_NONE 0
#define CADEX_LINK_URL  1
#define CADEX_LINK_PATH 2

typedef struct {
    uint8_t kind;       /* CADEX_LINK_* */
    uint16_t start_col; /* first and last cell on screen, to underline */
    uint16_t start_row;
    uint16_t end_col;
    uint16_t end_row;
} cadex_terminal_link;

_Static_assert(sizeof(cadex_terminal_link) == 10, "cadex_terminal_link layout");

/* The link at a viewport cell: an OSC 8 hyperlink, or a URL or existing
 * file path in the text (rows wrapped by width are joined). *target, not
 * NUL-terminated, is the URL or absolute path; free with cadex_free. No
 * link: kind CADEX_LINK_NONE and *target NULL. Call from the drawing thread:
 * it refreshes the frame, so a frame pointer taken before is stale. */
cadex_status cadex_terminal_link_at(cadex_terminal *terminal, uint16_t col, uint16_t row,
                                    cadex_terminal_link *out, uint8_t **target, size_t *target_len);

/* -- Mouse for programs, wheel and focus (core/features/terminal/mouse.zig) -- */

#define CADEX_MOUSE_TRACKING_NONE   0  /* select locally */
#define CADEX_MOUSE_TRACKING_CLICKS 1  /* presses and releases */
#define CADEX_MOUSE_TRACKING_DRAG   2  /* plus motion with a button down */
#define CADEX_MOUSE_TRACKING_MOTION 3  /* plus every motion */
uint8_t cadex_terminal_mouse_tracking(cadex_terminal *terminal);

#define CADEX_MOUSE_PRESS   0
#define CADEX_MOUSE_RELEASE 1
#define CADEX_MOUSE_MOTION  2

#define CADEX_MOUSE_BUTTON_NONE   0
#define CADEX_MOUSE_BUTTON_LEFT   1
#define CADEX_MOUSE_BUTTON_RIGHT  2
#define CADEX_MOUSE_BUTTON_MIDDLE 3

typedef struct {
    double x;               /* pixels from the view's top-left */
    double y;
    uint32_t view_width;    /* pixels */
    uint32_t view_height;
    uint16_t cell_width;    /* pixels */
    uint16_t cell_height;
    uint16_t padding;       /* pixels around the grid, the same on every side */
    uint8_t action;         /* CADEX_MOUSE_PRESS, _RELEASE, _MOTION */
    uint8_t button;         /* CADEX_MOUSE_BUTTON_*; motion with a button down is a drag */
    uint8_t mods;           /* CADEX_MOD_* */
} cadex_terminal_mouse_event;

_Static_assert(sizeof(cadex_terminal_mouse_event) == 40, "cadex_terminal_mouse_event layout");

/* A click, release or motion for the program, in the format it set;
 * nothing if it does not track the mouse. */
cadex_status cadex_terminal_mouse(cadex_terminal *terminal, const cadex_terminal_mouse_event *event);

/* The wheel, rows steps (negative is up): wheel reports if the program
 * tracks the mouse, arrow keys on the alternate screen (less, vim), or
 * scrolling the history. */
cadex_status cadex_terminal_wheel(cadex_terminal *terminal, const cadex_terminal_mouse_event *event, int32_t rows);

/* The view gained or lost keyboard focus: CSI I / CSI O if the program
 * asked for focus reports. */
cadex_status cadex_terminal_focus(cadex_terminal *terminal, bool focused);

/* -- Paste (core/features/terminal/paste.zig) -- */

/* Pastes text, encoded for the program: bracketed paste (ESC [ 200 ~ ...
 * ESC [ 201 ~) when it asked for it, newlines as Enter otherwise, control
 * bytes as spaces. Clears the selection and scrolls to the bottom. */
cadex_status cadex_terminal_paste(cadex_terminal *terminal, const uint8_t *bytes, size_t len);

/* False when pasting could run commands unseen: several lines without
 * bracketed paste, or text that ends the bracketed frame early. */
bool cadex_terminal_paste_is_safe(cadex_terminal *terminal, const uint8_t *bytes, size_t len);

/* Paths (NUL-terminated UTF-8) escaped for the shell (single quotes when
 * needed) and joined by spaces. Not NUL-terminated; free with cadex_free.
 * count 0: *out is NULL and *out_len is 0. */
cadex_status cadex_terminal_quote_paths(const char *const *paths, size_t count,
                                        uint8_t **out, size_t *out_len);

/* ---- Search (core/features/search) ------------------------------------ */

typedef struct {
    const uint8_t *text; /* UTF-8, not NUL-terminated */
    size_t len;
} cadex_text;

typedef struct {
    uint32_t index;            /* into the texts passed in */
    int32_t score;             /* higher is better */
    uint32_t positions_offset; /* into cadex_fuzzy_result.positions */
    uint32_t positions_count;  /* one per query character */
} cadex_fuzzy_match;

typedef struct {
    cadex_fuzzy_match *matches; /* best first */
    size_t count;
    uint32_t *positions;        /* byte offsets of the matched characters, to bold */
} cadex_fuzzy_result;

/* Fuzzy-ranks texts against a query: the query's characters must appear in
 * order; case and Portuguese accents do not matter; word starts rank
 * higher. An empty query keeps every text in order. Free the result with
 * cadex_fuzzy_result_free. */
cadex_status cadex_fuzzy_rank(const uint8_t *query, size_t query_len,
                              const cadex_text *texts, size_t count, cadex_fuzzy_result *out);
void cadex_fuzzy_result_free(cadex_fuzzy_result *result);

/* -- File names (⌘P) -- */

/* The file names of a folder (inside an authorized directory) in memory:
 * read on a thread of the core, then kept current by watching the disk.
 * .git, .gitignore'd and (unless show_hidden) hidden paths are left out;
 * symbolic links are not followed. Close with cadex_search_index_close. */
typedef struct cadex_search_index cadex_search_index;
cadex_status cadex_search_index_open(const char *root, bool show_hidden, cadex_search_index **out);
void cadex_search_index_close(cadex_search_index *index);
/* Files indexed so far; *ready (optional) turns true after the first full read. */
size_t cadex_search_index_count(cadex_search_index *index, bool *ready);

typedef struct {
    uint32_t path_offset; /* into cadex_search_files_result.paths; relative to the root */
    uint32_t path_len;    /* UTF-8, not NUL-terminated */
    int32_t score;
    uint32_t positions_offset; /* into cadex_search_files_result.positions */
    uint32_t positions_count;  /* byte offsets in the path of the matched characters */
} cadex_file_match;

typedef struct {
    cadex_file_match *matches; /* best first */
    size_t count;
    uint8_t *paths;
    uint32_t *positions;
} cadex_search_files_result;

/* The best `limit` paths for a fuzzy query; the file name counts more than
 * its folders. An empty query gives no matches. Fast enough per keystroke. */
cadex_status cadex_search_files(cadex_search_index *index, const uint8_t *query, size_t query_len,
                                size_t limit, cadex_search_files_result *out);
void cadex_search_files_result_free(cadex_search_files_result *result);

/* -- Content (⌘⇧F) -- */

typedef struct cadex_search_content cadex_search_content;

typedef struct {
    bool case_sensitive;
    bool regex;        /* POSIX extended syntax with Apple's \d \w \s \b (ADR 0009) */
    bool show_hidden;
    uint32_t max_results; /* 0: 2000 */
} cadex_search_content_options;

/* One line with a match; valid only during on_hits. */
typedef struct {
    const char *path;      /* relative to the root, NUL-terminated */
    uint32_t line;         /* 1-based */
    uint32_t column;       /* byte offset of the match in the line */
    const uint8_t *text;   /* the line around the match, at most 240 bytes */
    uint32_t text_len;
    uint32_t match_start;  /* the match inside text */
    uint32_t match_len;
} cadex_search_hit;

typedef struct {
    void *context;
    /* Batches of hits, on the search's thread. Must return quickly. */
    void (*on_hits)(void *context, const cadex_search_hit *hits, size_t count);
    /* The search ended by itself (not called after cancel). truncated:
     * stopped at max_results. files: how many were searched. */
    void (*on_done)(void *context, bool truncated, uint32_t files);
} cadex_search_content_callbacks;

/* Searches the files under root (.gitignore'd, binary and > 2 MB files are
 * skipped; one hit per line). An invalid regex: CADEX_INVALID_ARGUMENT. */
cadex_status cadex_search_content_start(const char *root, const uint8_t *query, size_t query_len,
                                        const cadex_search_content_options *options,
                                        const cadex_search_content_callbacks *callbacks,
                                        cadex_search_content **out);
/* Stops and frees; no callback runs after this returns. Not from inside a
 * callback. NULL is accepted. */
void cadex_search_content_cancel(cadex_search_content *search);

/* ---- Workspace (core/features/workspace) ------------------------------ */

/* Paths go in absolute and NUL-terminated. Paths that come out are
 * canonical (realpath), not NUL-terminated, freed with cadex_free; passing
 * NULL for out skips the copy. */

/* Authorizes an existing directory for this run of the app: file operations
 * and searches only act inside authorized directories. The list only grows. */
cadex_status cadex_workspace_authorize(const char *path, uint8_t **out, size_t *out_len);

/* Whether the path resolves (.., links) inside an authorized directory. */
bool cadex_workspace_is_authorized(const char *path);

/* Authorizes the current directory of a terminal session. Unknown directory:
 * CADEX_NOT_FOUND. */
cadex_status cadex_workspace_authorize_terminal(cadex_terminal *terminal, uint8_t **out, size_t *out_len);

/* The folder the app was opened with: the first of argv[1...] naming an
 * existing directory, relative ones resolved against cwd. macOS flags
 * (-psn_..., -NSKey value) are skipped. None: CADEX_OK with *out NULL. Not
 * authorized by this call. */
cadex_status cadex_workspace_launch_directory(const char *const *argv, size_t argc, const char *cwd,
                                              uint8_t **out, size_t *out_len);

/* ---- Explorer (core/features/explorer) -------------------------------- */

/* Every path must resolve inside an authorized directory (Workspace above),
 * or the call returns CADEX_NOT_AUTHORIZED. Paths that come out are
 * canonical, not NUL-terminated, freed with cadex_free. Deleting is the
 * app's (the system Trash). */

#define CADEX_ENTRY_FILE      0
#define CADEX_ENTRY_DIRECTORY 1
#define CADEX_ENTRY_SYMLINK   2
#define CADEX_ENTRY_OTHER     3

typedef struct {
    uint32_t name_offset; /* into cadex_explorer_listing.names */
    uint32_t name_len;    /* UTF-8, not NUL-terminated */
    uint8_t kind;         /* CADEX_ENTRY_* */
    bool link_to_directory; /* a symbolic link to a folder: sorted with folders */
    bool ignored;         /* left out by .gitignore, .ignore or .git/info/exclude */
    uint64_t size;        /* bytes, for files */
} cadex_explorer_entry;

typedef struct {
    cadex_explorer_entry *entries;
    size_t count;
    uint8_t *names;
} cadex_explorer_listing;

/* One folder: folders first, then files, natural order ignoring case
 * (file2 before file10); `.git` is left out. Free with
 * cadex_explorer_listing_free. CADEX_PERMISSION_DENIED: no read access. */
cadex_status cadex_explorer_list(const char *path, cadex_explorer_listing *out);
void cadex_explorer_listing_free(cadex_explorer_listing *listing);

/* Create an empty file or folder; CADEX_ALREADY_EXISTS if the name is taken. */
cadex_status cadex_explorer_create_file(const char *path);
cadex_status cadex_explorer_create_directory(const char *path);

/* New name in the same folder (a plain name, no slash). A taken name is
 * CADEX_ALREADY_EXISTS; a case-only change is allowed. *out: the new path. */
cadex_status cadex_explorer_rename(const char *path, const char *new_name, uint8_t **out, size_t *out_len);

/* Into the folder `destination`, same name. A folder into itself:
 * CADEX_INVALID_ARGUMENT. Taken name: CADEX_ALREADY_EXISTS. */
cadex_status cadex_explorer_move(const char *path, const char *destination, uint8_t **out, size_t *out_len);

/* Copy (folders with everything in them) into `destination`; next to a
 * namesake the copy is "name cópia.ext", then "name cópia 2.ext". */
cadex_status cadex_explorer_copy(const char *path, const char *destination, uint8_t **out, size_t *out_len);

/* A text file's bytes. max_size 0: 10 MB. Above it: CADEX_TOO_LARGE; a NUL
 * byte in the first 8 KB: CADEX_BINARY; a folder: CADEX_INVALID_ARGUMENT. */
cadex_status cadex_explorer_read_text(const char *path, uint64_t max_size, uint8_t **out, size_t *out_len);

/* At most max_size bytes (0: 10 MB) from the start, for a file too big to
 * show whole; *truncated (optional) is true when there is more. */
cadex_status cadex_explorer_read_text_head(const char *path, uint64_t max_size, uint8_t **out, size_t *out_len,
                                           bool *truncated);

/* Saves the bytes over the file, or creates it: written next to it and
 * renamed over, keeping its permissions. A symbolic link keeps pointing
 * to the replaced file. */
cadex_status cadex_explorer_write_text(const char *path, const uint8_t *data, size_t len);

/* -- Watching (FSEvents) -- */

typedef struct cadex_explorer_watcher cadex_explorer_watcher;

typedef struct {
    const char *path; /* the folder whose contents changed, canonical */
    bool subtree;     /* detail was lost: read everything below again */
} cadex_explorer_change;

/* Watches a folder and everything below it. on_change runs on the core's
 * watcher queue, each changed folder once per batch (~100 ms of changes);
 * it must return quickly, copy what it keeps, and not call
 * cadex_explorer_watch_stop. */
cadex_status cadex_explorer_watch(const char *path, void *context,
                                  void (*on_change)(void *context, const cadex_explorer_change *changes, size_t count),
                                  cadex_explorer_watcher **out);
/* No callback runs after this returns. NULL is accepted. */
void cadex_explorer_watch_stop(cadex_explorer_watcher *watcher);

/* ---- Editor (core/features/editor) ----------------------------------- */

/* Syntax colors and folds with tree-sitter (ADR 0006). Offsets are in units
 * of the text's encoding: bytes for UTF-8, code units for UTF-16 (the
 * encoding of NSString, so ranges map straight to NSRange). */

#define CADEX_TEXT_UTF8  0
#define CADEX_TEXT_UTF16 1 /* little-endian */

/* What a colored span is; the app picks the theme color. */
#define CADEX_TOKEN_KEYWORD     1
#define CADEX_TOKEN_STRING      2
#define CADEX_TOKEN_NUMBER      3
#define CADEX_TOKEN_COMMENT     4
#define CADEX_TOKEN_FUNCTION    5
#define CADEX_TOKEN_TYPE        6
#define CADEX_TOKEN_CONSTANT    7
#define CADEX_TOKEN_PROPERTY    8
#define CADEX_TOKEN_OPERATOR    9
#define CADEX_TOKEN_PUNCTUATION 10
#define CADEX_TOKEN_VARIABLE    11 /* builtins and parameters */
#define CADEX_TOKEN_TAG         12
#define CADEX_TOKEN_ATTRIBUTE   13
#define CADEX_TOKEN_ESCAPE      14
#define CADEX_TOKEN_HEADING     15
#define CADEX_TOKEN_LINK        16
#define CADEX_TOKEN_EMPHASIS    17

typedef struct cadex_editor_document cadex_editor_document;

typedef struct {
    uint32_t start;
    uint32_t end;
    uint8_t kind; /* CADEX_TOKEN_* */
} cadex_editor_span;

typedef struct {
    uint32_t start_row; /* 0-based */
    uint32_t end_row;   /* last row inside the region */
} cadex_editor_fold;

/* Parses the text with the language of file_name (by extension and a few
 * names). Unknown languages and texts above 1 MB are plain: no spans, no
 * folds. The text is copied. Close with cadex_editor_close. */
cadex_status cadex_editor_open(const char *file_name, const void *text, size_t len_bytes, uint8_t encoding,
                               cadex_editor_document **out);
void cadex_editor_close(cadex_editor_document *document);
/* "Zig", "TypeScript"...; NULL for plain text. Static, not freed. */
const char *cadex_editor_language(cadex_editor_document *document);

/* Replaces [start, old_end) with text (same encoding) and reparses only what
 * changed. *changed_start..*changed_end: the range to recolor. */
cadex_status cadex_editor_edit(cadex_editor_document *document, uint32_t start, uint32_t old_end,
                               const void *text, size_t len_bytes, uint32_t *changed_start, uint32_t *changed_end);

/* Non-overlapping colored spans in [start, end), in order. Free *out with
 * cadex_free (NULL when there are none). */
cadex_status cadex_editor_highlights(cadex_editor_document *document, uint32_t start, uint32_t end,
                                     cadex_editor_span **out, size_t *count);

/* Foldable regions of the whole text, by start row. Free with cadex_free. */
cadex_status cadex_editor_folds(cadex_editor_document *document, cadex_editor_fold **out, size_t *count);

/* ---- Markdown (core/features/markdown) ------------------------------- */

/* The rendered page's HTML body (md4c, ADR 0010): GitHub anchors, colored
 * code, `[[Note]]` as href="cadex-wiki:Note", raw HTML sanitized. Free with
 * cadex_free. */
cadex_status cadex_markdown_render(const uint8_t *text, size_t len, uint8_t **out, size_t *out_len);

/* The headings and links of every note of a folder, kept current from the
 * disk. Answers are lines of tab-separated fields (free with cadex_free);
 * paths in and out are absolute. */
typedef struct cadex_markdown_index cadex_markdown_index;
cadex_status cadex_markdown_index_open(const char *root, cadex_markdown_index **out);
void cadex_markdown_index_close(cadex_markdown_index *index);
bool cadex_markdown_index_ready(cadex_markdown_index *index);
/* One note path (relative to the root) per line. */
cadex_status cadex_markdown_notes(cadex_markdown_index *index, uint8_t **out, size_t *out_len);
/* "level \t line \t anchor \t text" per heading. CADEX_NOT_FOUND: not indexed. */
cadex_status cadex_markdown_headings(cadex_markdown_index *index, const char *path, uint8_t **out, size_t *out_len);
/* The links of an unsaved text (UTF-8) of the note at path: "start \t end
 * \t kind \t broken \t target \t line" per link. start/end in UTF-16 units;
 * kind 0 file, 1 wiki, 2 web; broken 0/1; target absolute or empty; line of
 * the heading named, 0 if none. */
cadex_status cadex_markdown_links(cadex_markdown_index *index, const char *path, const uint8_t *text, size_t len,
                                  uint8_t **out, size_t *out_len);
/* The notes linking to path: "absolute path \t line" per link. */
cadex_status cadex_markdown_backlinks(cadex_markdown_index *index, const char *path, uint8_t **out, size_t *out_len);
/* Where a destination written in the note at path goes (wiki: a note
 * name): "absolute path \t line \t broken". CADEX_NOT_FOUND: nowhere. */
cadex_status cadex_markdown_resolve(cadex_markdown_index *index, const char *path, const char *destination, bool wiki,
                                    uint8_t **out, size_t *out_len);

/* ---- Source control (core/features/source-control) ------------------- */

/* Everything runs the user's `git` (time limit, no password prompt, C
 * locale), only inside an authorized folder. Listings are lines of
 * tab-separated fields; a failed action returns CADEX_IO_FAILED with git's
 * message in *message (free with cadex_free). Paths in lists are relative
 * to the repository. */

bool cadex_git_available(void);
/* The repository's top folder; CADEX_NOT_FOUND when not in one. */
cadex_status cadex_git_root(const char *folder, uint8_t **out, size_t *out_len);
/* First line "branch \t oid \t upstream \t ahead \t behind" (branch empty when
 * detached, oid "(initial)" before the first commit); then per path "kind \t X
 * \t Y \t path \t orig": kind 0 changed, 1 renamed, 2 conflict, 3 untracked;
 * X/Y the index and work-tree letters (M A D R C T U ? .). */
cadex_status cadex_git_status(const char *repo, uint8_t **out, size_t *out_len);
cadex_status cadex_git_stage(const char *repo, const char *const *paths, size_t count, uint8_t **message, size_t *message_len);
cadex_status cadex_git_unstage(const char *repo, const char *const *paths, size_t count, uint8_t **message, size_t *message_len);
/* Drops work-tree changes of tracked paths (untracked ones: the Trash). */
cadex_status cadex_git_discard(const char *repo, const char *const *paths, size_t count, uint8_t **message, size_t *message_len);
/* Commits the staged changes, or every change with all. */
cadex_status cadex_git_commit(const char *repo, const char *text, bool all, uint8_t **message, size_t *message_len);
cadex_status cadex_git_fetch(const char *repo, uint8_t **message, size_t *message_len);
/* Fast-forward only: diverged branches are refused with a message. */
cadex_status cadex_git_pull(const char *repo, uint8_t **message, size_t *message_len);
/* Never forces. publish: push this branch to origin and track it; NULL: the upstream. */
cadex_status cadex_git_push(const char *repo, const char *publish, uint8_t **message, size_t *message_len);
/* "local \t name" / "remote \t name" per line, the current branch first. */
cadex_status cadex_git_branches(const char *repo, uint8_t **out, size_t *out_len);
/* remote: name is origin/x; a local branch x tracking it is created. */
cadex_status cadex_git_switch(const char *repo, const char *name, bool remote, uint8_t **message, size_t *message_len);
cadex_status cadex_git_init(const char *folder, uint8_t **message, size_t *message_len);

typedef struct {
    uint8_t *before; size_t before_len; /* HEAD (staged) or the index */
    uint8_t *after; size_t after_len;   /* the index (staged) or the disk */
    uint8_t *patch; size_t patch_len;   /* git diff of the path */
    bool binary;
    bool too_large; /* a side above 2 MB */
} cadex_git_diff_sides;
/* orig: the old name of a rename, or NULL. Free with cadex_git_diff_free. */
cadex_status cadex_git_diff(const char *repo, const char *path, const char *orig, bool staged, cadex_git_diff_sides *out);
/* A file as commit sha changed it: its first parent's version (nothing
 * for a root commit) and the commit's, and the patch. */
cadex_status cadex_git_diff_commit(const char *repo, const char *sha, const char *path, const char *orig, cadex_git_diff_sides *out);
void cadex_git_diff_free(cadex_git_diff_sides *diff);

/* ---- Git history (core/features/git-history) ------------------------- */

/* The log in pages, newest first, children before parents. Without a query,
 * each line carries the graph's lanes, continued from the page before.
 * Close with cadex_history_close. */
typedef struct cadex_history cadex_history;
/* query NULL or "": every commit with the graph (current_only: only what HEAD
 * reaches); otherwise the commits whose subject, author or sha match. */
cadex_status cadex_history_open(const char *repo, const char *query, bool current_only, cadex_history **out);
/* The next count commits (empty when the log ended), one per line:
 * "sha \t parents \t author \t email \t unix time \t refs \t subject \t column
 * \t color \t top \t bottom". parents are space-separated; column -1 without
 * a graph; top: segments "from,to,color" (space-separated) from a lane at the
 * row's top to the middle; bottom: from the middle to a lane at the bottom. */
cadex_status cadex_history_next(cadex_history *log, size_t count, uint8_t **out, size_t *out_len);
void cadex_history_close(cadex_history *log);
/* "parents \x1e message \x1e" then per file "letter \t added \t removed \t path
 * \t old path" (added/removed "-" for binary). A merge is compared with its
 * first parent. */
cadex_status cadex_history_details(const char *repo, const char *sha, uint8_t **out, size_t *out_len);
/* The commit's web page on origin (GitHub, GitLab, Bitbucket, Gitea...);
 * CADEX_NOT_FOUND without a known remote. */
cadex_status cadex_history_remote_url(const char *repo, const char *sha, uint8_t **out, size_t *out_len);

#ifdef __cplusplus
}
#endif

#endif /* CADEX_H */
