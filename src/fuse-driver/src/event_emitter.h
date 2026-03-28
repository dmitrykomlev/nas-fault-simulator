#ifndef EVENT_EMITTER_H
#define EVENT_EMITTER_H

#include <stdbool.h>
#include <stddef.h>
#include <sys/types.h>
#include "fs_common.h"

#define MAX_CORRUPTION_TRACK 256
#define EVENT_SOCKET_PATH_DEFAULT "/var/run/nas-emu/events.sock"

// Corruption detail collected during apply_corruption_fault
typedef struct {
    size_t count;
    size_t positions[MAX_CORRUPTION_TRACK];
    unsigned char original[MAX_CORRUPTION_TRACK];
    unsigned char corrupted[MAX_CORRUPTION_TRACK];
} corruption_detail_t;

// Initialize event emitter (create socket, set non-blocking)
void event_emitter_init(const char *socket_path);

// Cleanup event emitter
void event_emitter_cleanup(void);

// Emit a filesystem operation event (no fault)
void event_emit_op(fs_op_type_t op, const char *path,
                   off_t offset, size_t size, int result);

// Emit a fault event (error, delay, partial, timing, opcount)
void event_emit_fault(fs_op_type_t op, const char *path,
                      off_t offset, size_t size,
                      const char *fault_type, int fault_result);

// Emit a corruption event with byte-level details
void event_emit_corruption(fs_op_type_t op, const char *path,
                           off_t offset, size_t size,
                           const corruption_detail_t *detail);

#endif /* EVENT_EMITTER_H */
