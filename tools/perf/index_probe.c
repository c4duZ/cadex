// Measures the core's two workspace indexes through the C API, the way the
// apps use them (tools/perf/run.py): open on a root, focus a folder, wait
// for the first read, report count, seconds, memory and whether a file of
// the focus is in. Output: one line of key=value pairs.
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <mach/mach.h>
#include "cadex.h"

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static double footprint_mb(void) {
    task_vm_info_data_t v; mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
    task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&v, &n);
    return v.phys_footprint / 1048576.0;
}

// index_probe files|notes ROOT FOCUS NEEDLE
int main(int argc, char **argv) {
    if (argc < 5) return 2;
    const char *kind = argv[1], *root = argv[2], *focus = argv[3], *needle = argv[4];
    uint8_t *out = NULL; size_t len = 0;
    cadex_workspace_authorize(root, &out, &len); cadex_free(out);
    double m0 = footprint_mb(), t0 = now();
    size_t count = 0; int found = 0, partial = 0;
    if (strcmp(kind, "files") == 0) {
        cadex_search_index *ix = NULL;
        if (cadex_search_index_open(root, true, &ix) != CADEX_OK) return 1;
        cadex_search_index_focus(ix, focus);
        bool ready = false;
        while (!ready && now() - t0 < 120) { count = cadex_search_index_count(ix, &ready); usleep(50000); }
        partial = cadex_search_index_partial(ix);
        cadex_search_files_result r;
        if (cadex_search_files(ix, (const uint8_t *)needle, strlen(needle), 5, &r) == CADEX_OK) { found = r.count > 0; cadex_search_files_result_free(&r); }
        printf("count=%zu seconds=%.1f mb=%.0f found=%d partial=%d\n", count, now() - t0, footprint_mb() - m0, found, partial);
        cadex_search_index_close(ix);
    } else {
        cadex_markdown_index *ix = NULL;
        if (cadex_markdown_index_open(root, &ix) != CADEX_OK) return 1;
        cadex_markdown_index_focus(ix, focus);
        while (!cadex_markdown_index_ready(ix) && now() - t0 < 180) usleep(50000);
        out = NULL; cadex_markdown_notes(ix, &out, &len);
        for (size_t i = 0; i < len; i++) if (out[i] == '\n') count++;
        found = out && memmem(out, len, needle, strlen(needle)) != NULL;
        cadex_free(out);
        printf("count=%zu seconds=%.1f mb=%.0f found=%d partial=0\n", count, now() - t0, footprint_mb() - m0, found);
        cadex_markdown_index_close(ix);
    }
    return 0;
}
