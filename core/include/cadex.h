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

#ifdef __cplusplus
}
#endif

#endif /* CADEX_H */
