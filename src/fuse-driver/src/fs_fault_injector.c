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
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_GETATTR);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_GETATTR, &error_code))) {
        LOG_INFO("Error fault active for getattr: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_GETATTR);
    
    // Perform the actual operation
    return fs_op_getattr(path, stbuf);
}

static int fs_fault_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                           off_t offset, struct fuse_file_info *fi) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_READDIR);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_READDIR, &error_code))) {
        LOG_INFO("Error fault active for readdir: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_READDIR);
    
    // Perform the actual operation
    return fs_op_readdir(path, buf, filler, offset, fi);
}

static int fs_fault_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_CREATE);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_CREATE, &error_code))) {
        LOG_INFO("Error fault active for create: %s, returning error %d", path, error_code);
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
            return res;
        }
    }
    
    return fs_op_create(path, mode, fi);
}

static int fs_fault_mknod(const char *path, mode_t mode, dev_t rdev) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_MKNOD);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_MKNOD, &error_code))) {
        LOG_INFO("Error fault active for mknod: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_MKNOD);
    
    return fs_op_mknod(path, mode, rdev);
}

static int fs_fault_read(const char *path, char *buf, size_t size, off_t offset,
                        struct fuse_file_info *fi) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_READ);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_READ, &error_code))) {
        LOG_INFO("Error fault active for read: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_READ);
    
    // Check read permission if no file handle
    if (fi == NULL) {
        int res = fs_op_access(path, R_OK);
        if (res != 0) {
            LOG_DEBUG("Read denied due to permission check: %s", path);
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
    return res;
}

// In fs_fault_injector.c, the fs_fault_write function needs to be updated to properly check permissions

static int fs_fault_write(const char *path, const char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    LOG_INFO("=== WRITE OPERATION START ===");
    LOG_INFO("Path: %s, Size: %zu, Offset: %ld", path, size, offset);
    
    LOG_INFO("Step 1: Calling should_trigger_fault...");
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_WRITE);
    LOG_INFO("Step 1 complete: should_trigger_fault result: %s", should_fault ? "TRUE" : "FALSE");
    
    LOG_INFO("Step 2: Getting global config...");
    // Check if fault injection is enabled at all
    fs_config_t *config = config_get_global();
    LOG_INFO("Step 2 complete: Fault injection enabled: %s", config->enable_fault_injection ? "YES" : "NO");
    
    LOG_INFO("Step 3: Checking error fault...");
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_WRITE, &error_code))) {
        LOG_INFO("Error fault active for write: %s, returning error %d", path, error_code);
        return error_code;
    }
    LOG_INFO("Step 3 complete: No error fault triggered");
    
    LOG_INFO("Step 4: Checking delay fault...");
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_WRITE);
    LOG_INFO("Step 4 complete: Delay fault checked");
    
    LOG_INFO("Step 5: Checking write permissions...");
    // Always check write permission, regardless of whether we have a file handle
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_INFO("Write denied due to permission check: %s", path);
        return res;
    }
    LOG_INFO("Step 5 complete: Write permission OK");
    
    LOG_INFO("Step 6: Checking partial fault...");
    // 3. Apply partial operation fault if applicable
    size_t adjusted_size = apply_partial_fault(FS_OP_WRITE, size);
    LOG_INFO("Step 6 complete: Size after partial fault check: %zu (original: %zu)", adjusted_size, size);
    
    LOG_INFO("Step 7: Starting corruption fault check...");
    // 4. Handle corruption (create a local copy of the buffer and corrupt it)
    char *corrupted_buf = NULL;
    
    LOG_INFO("=== CORRUPTION FAULT CHECK ===");
    LOG_INFO("Config corruption_fault pointer: %p", config->corruption_fault);
    
    if (config->corruption_fault) {
        LOG_DEBUG("Corruption fault config found");
        bool should_affect = config_should_affect_operation(config->corruption_fault->operations_mask, FS_OP_WRITE);
        LOG_DEBUG("Should affect write operations: %s", should_affect ? "YES" : "NO");
        
        if (should_affect) {
            LOG_DEBUG("Checking corruption probability (should_fault=%s)...", should_fault ? "TRUE" : "FALSE");
            bool prob_result = check_probability(config->corruption_fault->probability);
            LOG_DEBUG("Probability check result: %s", prob_result ? "TRIGGERED" : "not triggered");
            
            if (should_fault || prob_result) {
                LOG_INFO("=== CORRUPTION TRIGGERED ===");
                
                // Create a copy of the buffer that we can corrupt
                corrupted_buf = malloc(adjusted_size);
                if (corrupted_buf) {
                    memcpy(corrupted_buf, buf, adjusted_size);
                    LOG_DEBUG("Created corruption buffer of size %zu", adjusted_size);
                    
                    // Apply corruption using the dedicated function
                    bool corruption_applied = apply_corruption_fault(FS_OP_WRITE, corrupted_buf, adjusted_size);
                    LOG_DEBUG("Corruption application result: %s", corruption_applied ? "SUCCESS" : "FAILED");
                    
                    if (!corruption_applied) {
                        LOG_WARN("Corruption was triggered but application failed");
                        free(corrupted_buf);
                        corrupted_buf = NULL;
                    }
                } else {
                    LOG_ERROR("Failed to allocate memory for corruption buffer");
                }
            } else {
                LOG_DEBUG("Corruption not triggered (probability check failed)");
            }
        } else {
            LOG_DEBUG("Write operations not affected by corruption configuration");
        }
    } else {
        LOG_DEBUG("No corruption fault configuration found");
    }
    
    // 5. Perform the actual operation with either the original or corrupted buffer
    const char *actual_buf = corrupted_buf ? corrupted_buf : buf;
    LOG_DEBUG("Performing write with %s buffer", corrupted_buf ? "CORRUPTED" : "original");
    res = fs_op_write(path, actual_buf, adjusted_size, offset, fi);
    LOG_DEBUG("Write operation result: %d", res);
    
    // Free our corrupted buffer if we created one
    if (corrupted_buf) {
        free(corrupted_buf);
        LOG_DEBUG("Freed corruption buffer");
    }
    
    // Update stats and return
    if (res > 0) {
        update_operation_stats(FS_OP_WRITE, res);
    }
    
    LOG_DEBUG("=== WRITE OPERATION END ===");
    return res;
}

static int fs_fault_open(const char *path, struct fuse_file_info *fi) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_OPEN);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_OPEN, &error_code))) {
        LOG_INFO("Error fault active for open: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_OPEN);
    
    // Check permissions based on flags
    if ((fi->flags & O_ACCMODE) == O_RDONLY) {
        int res = fs_op_access(path, R_OK);
        if (res != 0) {
            LOG_DEBUG("Open denied (read-only) due to permission check: %s", path);
            return res;
        }
    } else if ((fi->flags & O_ACCMODE) == O_WRONLY) {
        int res = fs_op_access(path, W_OK);
        if (res != 0) {
            LOG_DEBUG("Open denied (write-only) due to permission check: %s", path);
            return res;
        }
    } else if ((fi->flags & O_ACCMODE) == O_RDWR) {
        int res = fs_op_access(path, R_OK | W_OK);
        if (res != 0) {
            LOG_DEBUG("Open denied (read-write) due to permission check: %s", path);
            return res;
        }
    }
    
    return fs_op_open(path, fi);
}

static int fs_fault_release(const char *path, struct fuse_file_info *fi) {
    LOG_INFO("=== RELEASE OPERATION START ===");
    LOG_INFO("Release path: %s", path);
    
    LOG_INFO("Release step 1: Calling should_trigger_fault...");
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_RELEASE);
    LOG_INFO("Release step 1 complete: should_fault = %s", should_fault ? "TRUE" : "FALSE");
    
    LOG_INFO("Release step 2: Checking error fault...");
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_RELEASE, &error_code))) {
        LOG_INFO("Error fault active for release: %s, returning error %d", path, error_code);
        return error_code;
    }
    LOG_INFO("Release step 2 complete: No error fault");
    
    LOG_INFO("Release step 3: Checking delay fault...");
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_RELEASE);
    LOG_INFO("Release step 3 complete: Delay fault checked");
    
    LOG_INFO("Release step 4: Calling fs_op_release...");
    int result = fs_op_release(path, fi);
    LOG_INFO("Release step 4 complete: fs_op_release returned %d", result);
    
    LOG_INFO("=== RELEASE OPERATION END ===");
    return result;
}

static int fs_fault_mkdir(const char *path, mode_t mode) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_MKDIR);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_MKDIR, &error_code))) {
        LOG_INFO("Error fault active for mkdir: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_MKDIR);
    
    return fs_op_mkdir(path, mode);
}

static int fs_fault_rmdir(const char *path) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_RMDIR);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_RMDIR, &error_code))) {
        LOG_INFO("Error fault active for rmdir: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_RMDIR);
    
    return fs_op_rmdir(path);
}

static int fs_fault_unlink(const char *path) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_UNLINK);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_UNLINK, &error_code))) {
        LOG_INFO("Error fault active for unlink: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_UNLINK);
    
    return fs_op_unlink(path);
}

static int fs_fault_rename(const char *path, const char *newpath) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_RENAME);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_RENAME, &error_code))) {
        LOG_INFO("Error fault active for rename: %s to %s, returning error %d", path, newpath, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_RENAME);
    
    return fs_op_rename(path, newpath);
}

static int fs_fault_access(const char *path, int mode) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_ACCESS);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_ACCESS, &error_code))) {
        LOG_INFO("Error fault active for access: %s, mode: %d, returning error %d", path, mode, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_ACCESS);
    
    return fs_op_access(path, mode);
}

static int fs_fault_chmod(const char *path, mode_t mode) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_CHMOD);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_CHMOD, &error_code))) {
        LOG_INFO("Error fault active for chmod: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_CHMOD);
    
    // Check write permission
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("Chmod denied due to permission check: %s", path);
        return res;
    }
    
    return fs_op_chmod(path, mode);
}

static int fs_fault_chown(const char *path, uid_t uid, gid_t gid) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_CHOWN);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_CHOWN, &error_code))) {
        LOG_INFO("Error fault active for chown: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_CHOWN);
    
    // Check write permission
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("Chown denied due to permission check: %s", path);
        return res;
    }
    
    return fs_op_chown(path, uid, gid);
}

static int fs_fault_truncate(const char *path, off_t size) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_TRUNCATE);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_TRUNCATE, &error_code))) {
        LOG_INFO("Error fault active for truncate: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_TRUNCATE);
    
    // Check write permission
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("Truncate denied due to permission check: %s", path);
        return res;
    }
    
    return fs_op_truncate(path, size);
}

static int fs_fault_utimens(const char *path, const struct timespec ts[2]) {
    // First check if any timing or operation count conditions would trigger a fault
    bool should_fault = should_trigger_fault(FS_OP_UTIMENS);
    
    // Try each fault type in order of precedence
    
    // 1. Try error fault (highest precedence - returns error to caller)
    int error_code = -EIO;
    if ((should_fault || apply_error_fault(FS_OP_UTIMENS, &error_code))) {
        LOG_INFO("Error fault active for utimens: %s, returning error %d", path, error_code);
        return error_code;
    }
    
    // 2. Apply delay fault if applicable
    apply_delay_fault(FS_OP_UTIMENS);
    
    // Check write permission
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("Utimens denied due to permission check: %s", path);
        return res;
    }
    
    return fs_op_utimens(path, ts);
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