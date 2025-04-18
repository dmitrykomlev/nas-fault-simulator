#include "fs_common.h"

// String representation of operation types (for logging and config)
const char *fs_op_names[FS_OP_COUNT] = {
    "getattr",
    "readdir",
    "create",
    "mknod",
    "read",
    "write",
    "open",
    "release",
    "mkdir",
    "rmdir",
    "unlink",
    "rename",
    "access",
    "chmod",
    "chown",
    "truncate",
    "utimens"
};