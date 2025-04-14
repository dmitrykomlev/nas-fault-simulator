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
    if (should_trigger_fault("getattr")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for getattr: %s", path);
    }
    return fs_op_getattr(path, stbuf);
}

static int fs_fault_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                           off_t offset, struct fuse_file_info *fi) {
    if (should_trigger_fault("readdir")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for readdir: %s", path);
    }
    return fs_op_readdir(path, buf, filler, offset, fi);
}

static int fs_fault_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    if (should_trigger_fault("create")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for create: %s", path);
    }
    
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
    if (should_trigger_fault("mknod")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for mknod: %s", path);
    }
    return fs_op_mknod(path, mode, rdev);
}

static int fs_fault_read(const char *path, char *buf, size_t size, off_t offset,
                        struct fuse_file_info *fi) {
    if (should_trigger_fault("read")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for read: %s", path);
    }
    
    // Check read permission if no file handle
    if (fi == NULL) {
        int res = fs_op_access(path, R_OK);
        if (res != 0) {
            LOG_DEBUG("Read denied due to permission check: %s", path);
            return res;
        }
    }
    
    // Update operation statistics
    update_operation_stats("read", size);
    
    return fs_op_read(path, buf, size, offset, fi);
}

// In fs_fault_injector.c, the fs_fault_write function needs to be updated to properly check permissions

static int fs_fault_write(const char *path, const char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    if (should_trigger_fault("write")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for write: %s", path);
        }

        // Always check write permission, regardless of whether we have a file handle
        int res = fs_op_access(path, W_OK);
        if (res != 0) {
        LOG_DEBUG("Write denied due to permission check: %s", path);
        return res;
    }

    // Update operation statistics
    update_operation_stats("write", size);

    return fs_op_write(path, buf, size, offset, fi);
}

static int fs_fault_open(const char *path, struct fuse_file_info *fi) {
    if (should_trigger_fault("open")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for open: %s", path);
    }
    
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
    if (should_trigger_fault("release")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for release: %s", path);
    }
    return fs_op_release(path, fi);
}

static int fs_fault_mkdir(const char *path, mode_t mode) {
    if (should_trigger_fault("mkdir")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for mkdir: %s", path);
    }
    return fs_op_mkdir(path, mode);
}

static int fs_fault_rmdir(const char *path) {
    if (should_trigger_fault("rmdir")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for rmdir: %s", path);
    }
    return fs_op_rmdir(path);
}

static int fs_fault_unlink(const char *path) {
    if (should_trigger_fault("unlink")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for unlink: %s", path);
    }
    return fs_op_unlink(path);
}

static int fs_fault_rename(const char *path, const char *newpath) {
    if (should_trigger_fault("rename")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for rename: %s to %s", path, newpath);
    }
    return fs_op_rename(path, newpath);
}

static int fs_fault_access(const char *path, int mode) {
    if (should_trigger_fault("access")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for access: %s, mode: %d", path, mode);
    }
    return fs_op_access(path, mode);
}

static int fs_fault_chmod(const char *path, mode_t mode) {
    if (should_trigger_fault("chmod")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for chmod: %s", path);
    }
    
    // Check write permission
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("Chmod denied due to permission check: %s", path);
        return res;
    }
    
    return fs_op_chmod(path, mode);
}

static int fs_fault_chown(const char *path, uid_t uid, gid_t gid) {
    if (should_trigger_fault("chown")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for chown: %s", path);
    }
    
    // Check write permission
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("Chown denied due to permission check: %s", path);
        return res;
    }
    
    return fs_op_chown(path, uid, gid);
}

static int fs_fault_truncate(const char *path, off_t size) {
    if (should_trigger_fault("truncate")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for truncate: %s", path);
    }
    
    // Check write permission
    int res = fs_op_access(path, W_OK);
    if (res != 0) {
        LOG_DEBUG("Truncate denied due to permission check: %s", path);
        return res;
    }
    
    return fs_op_truncate(path, size);
}

static int fs_fault_utimens(const char *path, const struct timespec ts[2]) {
    if (should_trigger_fault("utimens")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for utimens: %s", path);
    }
    
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