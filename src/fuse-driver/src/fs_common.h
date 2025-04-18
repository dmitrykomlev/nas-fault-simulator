#ifndef FS_COMMON_H
#define FS_COMMON_H

// File system operation types
typedef enum {
    FS_OP_GETATTR = 0,
    FS_OP_READDIR,
    FS_OP_CREATE,
    FS_OP_MKNOD,
    FS_OP_READ,
    FS_OP_WRITE,
    FS_OP_OPEN,
    FS_OP_RELEASE,
    FS_OP_MKDIR,
    FS_OP_RMDIR,
    FS_OP_UNLINK,
    FS_OP_RENAME,
    FS_OP_ACCESS,
    FS_OP_CHMOD,
    FS_OP_CHOWN,
    FS_OP_TRUNCATE,
    FS_OP_UTIMENS,
    /* Add new operations here */
    FS_OP_COUNT  /* Total number of operations */
} fs_op_type_t;

// String representation of operation types (for logging and config)
extern const char *fs_op_names[FS_OP_COUNT];

#endif // FS_COMMON_H