#define FUSE_USE_VERSION 26

#include <fuse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <stddef.h>  /* For offsetof macro */

#include "fs_operations.h"
#include "fault_injector.h"
#include "log.h"
#include "config.h"

// Define our own help key that doesn't conflict with FUSE's constants
#define NAS_OPT_KEY_HELP -100

// Command line options structure
struct fs_fault_options {
    char *storage_path;
    char *log_file;
    int log_level;
    char *config_file;
    int show_help;
};

// Global configuration
static fs_config_t *config;

// Wrapper functions that can inject faults
static int fs_fault_getattr(const char *path, struct stat *stbuf) {
    LOG_DEBUG(">>> ENTER getattr: %s", path);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_GETATTR);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_GETATTR, &error_code)) {
        LOG_INFO("Error fault active for getattr: %s, returning error %d", path, error_code);
        LOG_DEBUG("<<< EXIT getattr: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_GETATTR);
    
    // Perform the actual operation
    int result = fs_op_getattr(path, stbuf);
    LOG_DEBUG("<<< EXIT getattr: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                           off_t offset, struct fuse_file_info *fi) {
    LOG_DEBUG(">>> ENTER readdir: %s (offset: %ld)", path, offset);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_READDIR);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_READDIR, &error_code)) {
        LOG_INFO("Error fault active for readdir: %s, returning error %d", path, error_code);
        LOG_DEBUG("<<< EXIT readdir: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_READDIR);
    
    // Perform the actual operation
    int result = fs_op_readdir(path, buf, filler, offset, fi);
    LOG_DEBUG("<<< EXIT readdir: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    LOG_DEBUG(">>> ENTER create: %s (mode: %o)", path, mode);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_CREATE);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_CREATE, &error_code)) {
        LOG_INFO("Error fault active for create: %s, returning error %d", path, error_code);
        LOG_DEBUG("<<< EXIT create: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_CREATE);
    
    // First, check access permissions if the file already exists
    struct stat st;
    if (fs_op_getattr(path, &st) == 0) {
        int res = fs_op_access(path, W_OK);
        if (res != 0) {
            LOG_DEBUG("Create denied due to permission check: %s", path);
            LOG_DEBUG("<<< EXIT create: %s (permission denied: %d)", path, res);
            return res;
        }
    }
    
    int result = fs_op_create(path, mode, fi);
    LOG_DEBUG("<<< EXIT create: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_mknod(const char *path, mode_t mode, dev_t rdev) {
    LOG_DEBUG(">>> ENTER mknod: %s (mode: %o)", path, mode);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_MKNOD);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_MKNOD, &error_code)) {
        LOG_INFO("Error fault active for mknod: %s, returning error %d", path, error_code);
        LOG_DEBUG("<<< EXIT mknod: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_MKNOD);
    
    int result = fs_op_mknod(path, mode, rdev);
    LOG_DEBUG("<<< EXIT mknod: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_read(const char *path, char *buf, size_t size, off_t offset,
                        struct fuse_file_info *fi) {
    LOG_DEBUG(">>> ENTER read: %s (size: %zu, offset: %ld)", path, size, offset);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_READ);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_READ, &error_code)) {
        LOG_INFO("Error fault active for read: %s, returning error %d", path, error_code);
        LOG_DEBUG("<<< EXIT read: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_READ);
    
    // Check read permission if no file handle
    if (fi == NULL) {
        int res = fs_op_access(path, R_OK);
        if (res != 0) {
            LOG_DEBUG("Read denied due to permission check: %s", path);
            LOG_DEBUG("<<< EXIT read: %s (permission denied: %d)", path, res);
            return res;
        }
    }
    
    // 3. Apply partial operation fault if applicable
    size_t adjusted_size = apply_partial_fault(FS_OP_READ, size);
    
    // 4. Perform the actual operation
    int res = fs_op_read(path, buf, adjusted_size, offset, fi);
    
    // Update stats and return
    if (res > 0) {
        update_operation_stats(FS_OP_READ, res);
    }
    LOG_DEBUG("<<< EXIT read: %s (result: %d)", path, res);
    return res;
}

// In fs_fault_injector.c, the fs_fault_write function needs to be updated to properly check permissions

static int fs_fault_write(const char *path, const char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    LOG_DEBUG(">>> ENTER write: %s (size: %zu, offset: %ld)", path, size, offset);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_WRITE);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_WRITE, &error_code)) {
        LOG_INFO("Error fault active for write: %s, returning error %d", path, error_code);
        LOG_DEBUG("<<< EXIT write: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_WRITE);
    
    // Check write permission if no file handle
    if (fi == NULL) {
        int res = fs_op_access(path, W_OK);
        if (res != 0) {
            LOG_DEBUG("Write denied due to permission check: %s", path);
            LOG_DEBUG("<<< EXIT write: %s (permission denied: %d)", path, res);
            return res;
        }
    }
    
    // 3. Apply partial operation fault if applicable
    size_t adjusted_size = apply_partial_fault(FS_OP_WRITE, size);
    
    // 4. Apply corruption fault if applicable
    char *corrupted_buf = NULL;
    // Create a temporary copy to test if corruption should be applied
    char *temp_buf = malloc(adjusted_size);
    if (temp_buf) {
        memcpy(temp_buf, buf, adjusted_size);
        if (apply_corruption_fault(FS_OP_WRITE, temp_buf, adjusted_size)) {
            // Corruption was applied to temp_buf, use it as the corrupted buffer
            corrupted_buf = temp_buf;
            temp_buf = NULL; // Transfer ownership
        } else {
            // No corruption applied, free the temp buffer
            free(temp_buf);
        }
    }
    
    // 5. Perform the actual operation
    const char *final_buf = corrupted_buf ? corrupted_buf : buf;
    int res = fs_op_write(path, final_buf, adjusted_size, offset, fi);
    
    // Cleanup
    if (corrupted_buf) {
        free(corrupted_buf);
    }
    
    // Update stats and return
    if (res > 0) {
        update_operation_stats(FS_OP_WRITE, res);
    }
    LOG_DEBUG("<<< EXIT write: %s (result: %d)", path, res);
    return res;
}

static int fs_fault_open(const char *path, struct fuse_file_info *fi) {
    LOG_DEBUG(">>> ENTER open: %s (flags: 0x%x)", path, fi->flags);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_OPEN);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_OPEN, &error_code)) {
        LOG_DEBUG("<<< EXIT open: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_OPEN);
    
    // Check permissions based on flags
    if ((fi->flags & O_ACCMODE) == O_RDONLY) {
        int res = fs_op_access(path, R_OK);
        if (res != 0) {
            LOG_DEBUG("<<< EXIT open: %s (permission denied: %d)", path, res);
            return res;
        }
    } else if ((fi->flags & O_ACCMODE) == O_WRONLY) {
        int res = fs_op_access(path, W_OK);
        if (res != 0) {
            LOG_DEBUG("<<< EXIT open: %s (permission denied: %d)", path, res);
            return res;
        }
    } else if ((fi->flags & O_ACCMODE) == O_RDWR) {
        int res = fs_op_access(path, R_OK | W_OK);
        if (res != 0) {
            LOG_DEBUG("<<< EXIT open: %s (permission denied: %d)", path, res);
            return res;
        }
    }
    
    int result = fs_op_open(path, fi);
    LOG_DEBUG("<<< EXIT open: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_release(const char *path, struct fuse_file_info *fi) {
    LOG_DEBUG(">>> ENTER release: %s", path);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_RELEASE);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_RELEASE, &error_code)) {
        LOG_DEBUG("<<< EXIT release: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_RELEASE);
    
    int result = fs_op_release(path, fi);
    LOG_DEBUG("<<< EXIT release: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_mkdir(const char *path, mode_t mode) {
    LOG_DEBUG(">>> ENTER mkdir: %s (mode: %o)", path, mode);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_MKDIR);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_MKDIR, &error_code)) {
        LOG_DEBUG("<<< EXIT mkdir: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_MKDIR);
    
    int result = fs_op_mkdir(path, mode);
    LOG_DEBUG("<<< EXIT mkdir: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_rmdir(const char *path) {
    LOG_DEBUG(">>> ENTER rmdir: %s", path);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_RMDIR);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_RMDIR, &error_code)) {
        LOG_DEBUG("<<< EXIT rmdir: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_RMDIR);
    
    int result = fs_op_rmdir(path);
    LOG_DEBUG("<<< EXIT rmdir: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_unlink(const char *path) {
    LOG_DEBUG(">>> ENTER unlink: %s", path);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_UNLINK);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_UNLINK, &error_code)) {
        LOG_DEBUG("<<< EXIT unlink: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_UNLINK);
    
    int result = fs_op_unlink(path);
    LOG_DEBUG("<<< EXIT unlink: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_rename(const char *path, const char *newpath) {
    LOG_DEBUG(">>> ENTER rename: %s to %s", path, newpath);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_RENAME);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_RENAME, &error_code)) {
        LOG_DEBUG("<<< EXIT rename: %s to %s (error fault: %d)", path, newpath, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_RENAME);
    
    int result = fs_op_rename(path, newpath);
    LOG_DEBUG("<<< EXIT rename: %s to %s (result: %d)", path, newpath, result);
    return result;
}

static int fs_fault_access(const char *path, int mode) {
    LOG_DEBUG(">>> ENTER access: %s (mode: %d)", path, mode);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_ACCESS);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_ACCESS, &error_code)) {
        LOG_DEBUG("<<< EXIT access: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_ACCESS);
    
    int result = fs_op_access(path, mode);
    LOG_DEBUG("<<< EXIT access: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_chmod(const char *path, mode_t mode) {
    LOG_DEBUG(">>> ENTER chmod: %s (mode: %o)", path, mode);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_CHMOD);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_CHMOD, &error_code)) {
        LOG_DEBUG("<<< EXIT chmod: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_CHMOD);
    
    // Check write permission
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("<<< EXIT chmod: %s (permission denied: %d)", path, res);
        return res;
    }
    
    int result = fs_op_chmod(path, mode);
    LOG_DEBUG("<<< EXIT chmod: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_chown(const char *path, uid_t uid, gid_t gid) {
    LOG_DEBUG(">>> ENTER chown: %s (uid: %d, gid: %d)", path, uid, gid);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_CHOWN);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_CHOWN, &error_code)) {
        LOG_DEBUG("<<< EXIT chown: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_CHOWN);
    
    // Check write permission
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("<<< EXIT chown: %s (permission denied: %d)", path, res);
        return res;
    }
    
    int result = fs_op_chown(path, uid, gid);
    LOG_DEBUG("<<< EXIT chown: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_truncate(const char *path, off_t size) {
    LOG_DEBUG(">>> ENTER truncate: %s (size: %ld)", path, size);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_TRUNCATE);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_TRUNCATE, &error_code)) {
        LOG_DEBUG("<<< EXIT truncate: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_TRUNCATE);
    
    // Check write permission
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("<<< EXIT truncate: %s (permission denied: %d)", path, res);
        return res;
    }
    
    int result = fs_op_truncate(path, size);
    LOG_DEBUG("<<< EXIT truncate: %s (result: %d)", path, result);
    return result;
}

static int fs_fault_utimens(const char *path, const struct timespec ts[2]) {
    LOG_DEBUG(">>> ENTER utimens: %s", path);
    
    // Check timing/count-based faults first
    bool timing_count_fault = should_trigger_fault(FS_OP_UTIMENS);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if (timing_count_fault || apply_error_fault(FS_OP_UTIMENS, &error_code)) {
        LOG_DEBUG("<<< EXIT utimens: %s (error fault: %d)", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_UTIMENS);
    
    // Check write permission
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("<<< EXIT utimens: %s (permission denied: %d)", path, res);
        return res;
    }
    
    int result = fs_op_utimens(path, ts);
    LOG_DEBUG("<<< EXIT utimens: %s (result: %d)", path, result);
    return result;
}

static struct fuse_operations fs_fault_oper = {
    .getattr  = fs_fault_getattr,
    .readdir  = fs_fault_readdir,
    .mknod    = fs_fault_mknod,
    .mkdir    = fs_fault_mkdir,
    .unlink   = fs_fault_unlink,
    .rmdir    = fs_fault_rmdir,
    .rename   = fs_fault_rename,
    .open     = fs_fault_open,
    .read     = fs_fault_read,
    .write    = fs_fault_write,
    .release  = fs_fault_release,
    .create   = fs_fault_create,
    .chmod    = fs_fault_chmod,
    .chown    = fs_fault_chown,
    .truncate = fs_fault_truncate,
    .utimens  = fs_fault_utimens,
    .access   = fs_fault_access,
};

// Helper function to display usage information
static void show_help(const char *progname) {
    printf("Usage: %s mountpoint [options]\n\n", progname);
    printf("NAS Emulator FUSE Driver - A filesystem with fault injection capabilities\n\n");
    printf("Options:\n");
    printf("    --storage=PATH         Path to storage directory (default: /var/nas-storage)\n");
    printf("    --log=PATH             Path to log file (default: stdout)\n");
    printf("    --loglevel=LEVEL       Log level (0-3, default: 2)\n");
    printf("    --config=PATH          Path to configuration file\n");
    printf("    -h, --help             Display this help message\n\n");
    printf("FUSE options:\n");
    
    // Let FUSE print its help message
    struct fuse_args args = FUSE_ARGS_INIT(0, NULL);
    fuse_opt_add_arg(&args, progname);
    fuse_opt_add_arg(&args, "-h");
    fuse_parse_cmdline(&args, NULL, NULL, NULL);
    fuse_opt_free_args(&args);
}

// FUSE option processing function
static int fs_fault_opt_proc(void *data, const char *arg, int key, struct fuse_args *outargs) {
    struct fs_fault_options *options = (struct fs_fault_options*)data;
    
    if (key == FUSE_OPT_KEY_NONOPT && outargs->argc == 1) {
        // First non-option argument is the mount point, keep it
        return 1;
    }
    
    // Handle custom options
    switch (key) {
        case FUSE_OPT_KEY_OPT:
            // Handle options in FUSE
            return 1;
            
        case FUSE_OPT_KEY_NONOPT:
            // Ignore other non-option arguments
            return 1;
            
        case NAS_OPT_KEY_HELP: // Using our custom help key
            options->show_help = 1;
            return 0;
    }
    
    return 1;  // Keep all other arguments
}

// FUSE option specification
static struct fuse_opt fs_fault_opts[] = {
    {"--storage=%s", offsetof(struct fs_fault_options, storage_path), 0},
    {"--log=%s", offsetof(struct fs_fault_options, log_file), 0},
    {"--loglevel=%d", offsetof(struct fs_fault_options, log_level), 0},
    {"--config=%s", offsetof(struct fs_fault_options, config_file), 0},
    {"-h", NAS_OPT_KEY_HELP, 0}, // Using our custom help key
    {"--help", NAS_OPT_KEY_HELP, 0}, // Using our custom help key
    FUSE_OPT_END
};

int main(int argc, char *argv[]) {
    int ret;
    struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
    struct fs_fault_options options;
    
    // Set default option values
    memset(&options, 0, sizeof(options));
    
    // Parse command line options
    if (fuse_opt_parse(&args, &options, fs_fault_opts, fs_fault_opt_proc) == -1) {
        return 1;
    }
    
    // Show help if requested
    if (options.show_help) {
        show_help(argv[0]);
        fuse_opt_free_args(&args);
        return 0;
    }
    
    // Initialize global configuration
    config = config_get_global();
    config_init(config);
    
    // Load configuration from file if specified
    if (options.config_file) {
        if (!config_load_from_file(config, options.config_file)) {
            fprintf(stderr, "Warning: Failed to load configuration from %s\n", options.config_file);
        }
    }
    
    // Override config with command line options if specified
    if (options.storage_path) {
        free(config->storage_path);
        config->storage_path = strdup(options.storage_path);
    }
    
    if (options.log_file) {
        free(config->log_file);
        config->log_file = strdup(options.log_file);
    }
    
    if (options.log_level) {
        config->log_level = options.log_level;
    }
    
    // Print configuration
    config_print(config);
    
    // Initialize logging
    log_init(config->log_file, config->log_level);
    LOG_INFO("Filesystem Fault Injector initializing...");
    LOG_INFO("Log level set to: %d (0=ERROR, 1=WARN, 2=INFO, 3=DEBUG)", config->log_level);
    LOG_INFO("Using storage path: %s", config->storage_path);
    
    // Create storage directory if it doesn't exist
    mkdir(config->storage_path, 0755);
    
    // Initialize filesystem operations
    fs_ops_init(config->storage_path);
    
    // Initialize fault injector
    fault_injector_init();
    
    // Run FUSE main loop
    ret = fuse_main(args.argc, args.argv, &fs_fault_oper, NULL);
    
    // Clean up resources
    fs_ops_cleanup();
    fault_injector_cleanup();
    
    // Clean up logging
    log_close();
    
    // Clean up configuration
    config_cleanup(config);
    
    // Free command line option strings
    free(options.storage_path);
    free(options.log_file);
    free(options.config_file);
    
    // Free FUSE arguments
    fuse_opt_free_args(&args);
    
    return ret;
}