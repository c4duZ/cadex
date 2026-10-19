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

/* New size in cells, plus the cell size in pixels (programs may ask for it). */
cadex_status cadex_terminal_resize(cadex_terminal *terminal, uint16_t cols, uint16_t rows,
                                   uint16_t cell_width_px, uint16_t cell_height_px);

/* True while a program other than the shell runs in the foreground. */
bool cadex_terminal_has_foreground_process(cadex_terminal *terminal);

/* Visible text, one line per row, not NUL-terminated. Free with cadex_free.
 * Empty screen: *out is NULL and *out_len is 0. */
cadex_status cadex_terminal_copy_text(cadex_terminal *terminal, uint8_t **out, size_t *out_len);

#ifdef __cplusplus
}
#endif

#endif /* CADEX_H */
