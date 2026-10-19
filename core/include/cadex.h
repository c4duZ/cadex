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
} cadex_terminal_frame;

/* Layout shared with render.zig, which asserts the same sizes. */
_Static_assert(sizeof(cadex_terminal_cell) == 16, "cadex_terminal_cell layout");
_Static_assert(sizeof(cadex_terminal_frame) == 48, "cadex_terminal_frame layout");

/* Captures the screen for drawing. Call only from the thread that draws;
 * the frame stays valid until the next call or cadex_terminal_close. */
cadex_status cadex_terminal_update_frame(cadex_terminal *terminal, const cadex_terminal_frame **out);

/* Visible text, one line per row, not NUL-terminated. Free with cadex_free.
 * Empty screen: *out is NULL and *out_len is 0. */
cadex_status cadex_terminal_copy_text(cadex_terminal *terminal, uint8_t **out, size_t *out_len);

#ifdef __cplusplus
}
#endif

#endif /* CADEX_H */
