/* Cadex core C API. The only door from the apps into the core (ADR 0002).
 *
 * Conventions:
 * - Functions are prefixed cadex_<feature>_.
 * - Every call that can fail returns a cadex_status; 0 is success.
 * - Whoever allocates frees: buffers returned by the core are released with
 *   the matching cadex_*_free call.
 */
#ifndef CADEX_H
#define CADEX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t cadex_status;

#define CADEX_OK 0

#ifdef __cplusplus
}
#endif

#endif /* CADEX_H */
