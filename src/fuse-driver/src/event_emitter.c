#include "event_emitter.h"
#include "log.h"
#include "config.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <sys/socket.h>
#include <sys/un.h>

// Socket state
static int emit_fd = -1;
static struct sockaddr_un dest_addr;
static size_t events_dropped = 0;
static bool initialized = false;

// Max datagram size (stay well under kernel limit)
#define MAX_EVENT_SIZE 4096

// Get current time as epoch milliseconds
static uint64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}

// Send a buffer to the socket (non-blocking, silently drops on failure)
static void emit_send(const char *buf, size_t len) {
    if (!initialized || emit_fd < 0) return;

    fs_config_t *config = config_get_global();
    if (!config->event_emission_enabled) return;

    ssize_t sent = sendto(emit_fd, buf, len, 0,
                          (struct sockaddr *)&dest_addr, sizeof(dest_addr));
    if (sent < 0) {
        events_dropped++;
        if (events_dropped % 1000 == 1) {
            LOG_DEBUG("Event emitter: %zu events dropped (last errno: %d)",
                      events_dropped, errno);
        }
    }
}

// Check if an operation should be emitted
static bool should_emit(fs_op_type_t op) {
    fs_config_t *config = config_get_global();
    if (!config->event_emission_enabled) return false;

    // Always emit data operations and faults
    if (op == FS_OP_READ || op == FS_OP_WRITE || op == FS_OP_CREATE ||
        op == FS_OP_TRUNCATE || op == FS_OP_UNLINK || op == FS_OP_RENAME ||
        op == FS_OP_MKNOD) {
        return true;
    }

    // Metadata ops only if configured
    return config->emit_metadata_ops;
}

void event_emitter_init(const char *socket_path) {
    if (!socket_path) socket_path = EVENT_SOCKET_PATH_DEFAULT;

    emit_fd = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (emit_fd < 0) {
        LOG_WARN("Event emitter: failed to create socket: %s", strerror(errno));
        return;
    }

    // Set non-blocking
    int flags = fcntl(emit_fd, F_GETFL, 0);
    fcntl(emit_fd, F_SETFL, flags | O_NONBLOCK);

    // Set up destination address
    memset(&dest_addr, 0, sizeof(dest_addr));
    dest_addr.sun_family = AF_UNIX;
    strncpy(dest_addr.sun_path, socket_path, sizeof(dest_addr.sun_path) - 1);

    initialized = true;
    events_dropped = 0;

    LOG_INFO("Event emitter initialized (socket: %s)", socket_path);
}

void event_emitter_cleanup(void) {
    if (emit_fd >= 0) {
        close(emit_fd);
        emit_fd = -1;
    }
    initialized = false;
    LOG_INFO("Event emitter cleanup (dropped: %zu)", events_dropped);
}

void event_emit_op(fs_op_type_t op, const char *path,
                   off_t offset, size_t size, int result) {
    if (!should_emit(op)) return;

    char buf[MAX_EVENT_SIZE];
    int len = snprintf(buf, sizeof(buf),
        "{\"ts\":%llu,\"op\":\"%s\",\"path\":\"%s\","
        "\"off\":%lld,\"sz\":%zu,\"res\":%d,\"fault\":null}",
        (unsigned long long)now_ms(),
        fs_op_names[op],
        path ? path : "",
        (long long)offset,
        size,
        result);

    if (len > 0 && (size_t)len < sizeof(buf)) {
        emit_send(buf, (size_t)len);
        LOG_DEBUG("Event emitted: op=%s path=%s off=%lld sz=%zu res=%d",
                  fs_op_names[op], path ? path : "", (long long)offset, size, result);
    }
}

void event_emit_fault(fs_op_type_t op, const char *path,
                      off_t offset, size_t size,
                      const char *fault_type, int fault_result) {
    char buf[MAX_EVENT_SIZE];
    int len = snprintf(buf, sizeof(buf),
        "{\"ts\":%llu,\"op\":\"%s\",\"path\":\"%s\","
        "\"off\":%lld,\"sz\":%zu,\"res\":%d,\"fault\":\"%s\"}",
        (unsigned long long)now_ms(),
        fs_op_names[op],
        path ? path : "",
        (long long)offset,
        size,
        fault_result,
        fault_type);

    if (len > 0 && (size_t)len < sizeof(buf)) {
        emit_send(buf, (size_t)len);
        LOG_DEBUG("Event emitted: fault=%s op=%s path=%s res=%d",
                  fault_type, fs_op_names[op], path ? path : "", fault_result);
    }
}

void event_emit_corruption(fs_op_type_t op, const char *path,
                           off_t offset, size_t size,
                           const corruption_detail_t *detail) {
    if (!detail || detail->count == 0) return;

    char buf[MAX_EVENT_SIZE];
    int pos = 0;

    // Header
    pos += snprintf(buf + pos, sizeof(buf) - pos,
        "{\"ts\":%llu,\"op\":\"%s\",\"path\":\"%s\","
        "\"off\":%lld,\"sz\":%zu,\"res\":%zu,"
        "\"fault\":\"corruption\",\"corr\":{\"n\":%zu,\"pos\":[",
        (unsigned long long)now_ms(),
        fs_op_names[op],
        path ? path : "",
        (long long)offset,
        size,
        size,  // result = size (corruption doesn't change return value)
        detail->count);

    // Positions array
    size_t emit_count = detail->count;
    if (emit_count > MAX_CORRUPTION_TRACK) emit_count = MAX_CORRUPTION_TRACK;

    for (size_t i = 0; i < emit_count && pos < (int)(sizeof(buf) - 200); i++) {
        if (i > 0) buf[pos++] = ',';
        pos += snprintf(buf + pos, sizeof(buf) - pos, "%zu", detail->positions[i]);
    }

    // Original values array
    pos += snprintf(buf + pos, sizeof(buf) - pos, "],\"orig\":[");
    for (size_t i = 0; i < emit_count && pos < (int)(sizeof(buf) - 200); i++) {
        if (i > 0) buf[pos++] = ',';
        pos += snprintf(buf + pos, sizeof(buf) - pos, "%u", detail->original[i]);
    }

    // Corrupted values array
    pos += snprintf(buf + pos, sizeof(buf) - pos, "],\"new\":[");
    for (size_t i = 0; i < emit_count && pos < (int)(sizeof(buf) - 200); i++) {
        if (i > 0) buf[pos++] = ',';
        pos += snprintf(buf + pos, sizeof(buf) - pos, "%u", detail->corrupted[i]);
    }

    // Close
    bool truncated = (detail->count > MAX_CORRUPTION_TRACK) ||
                     (pos >= (int)(sizeof(buf) - 200));
    pos += snprintf(buf + pos, sizeof(buf) - pos,
        "],\"truncated\":%s}}", truncated ? "true" : "false");

    if (pos > 0 && (size_t)pos < sizeof(buf)) {
        emit_send(buf, (size_t)pos);
        LOG_DEBUG("Event emitted: corruption op=%s path=%s n=%zu",
                  fs_op_names[op], path ? path : "", detail->count);
    }
}
