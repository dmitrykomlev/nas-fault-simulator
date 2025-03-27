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

// Default storage path
static const char *default_storage_path = "/tmp/fs_fault_storage";

// Command line options structure
struct fs_fault_config {
    char *storage_path;
    char *log_file;
    int log_level;
};

// Global configuration
static struct fs_fault_config config;

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
    
    // Update operation statistics
    update_operation_stats("read", size);
    
    return fs_op_read(path, buf, size, offset, fi);
}

static int fs_fault_write(const char *path, const char *buf, size_t size,
                         off_t offset, struct fuse_file_info *fi) {
    if (should_trigger_fault("write")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for write: %s", path);
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

// Add wrapper functions for the new operations

static int fs_fault_chmod(const char *path, mode_t mode) {
    if (should_trigger_fault("chmod")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for chmod: %s", path);
    }
    return fs_op_chmod(path, mode);
}

static int fs_fault_chown(const char *path, uid_t uid, gid_t gid) {
    if (should_trigger_fault("chown")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for chown: %s", path);
    }
    return fs_op_chown(path, uid, gid);
}

static int fs_fault_truncate(const char *path, off_t size) {
    if (should_trigger_fault("truncate")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for truncate: %s", path);
    }
    return fs_op_truncate(path, size);
}

static int fs_fault_utimens(const char *path, const struct timespec ts[2]) {
    if (should_trigger_fault("utimens")) {
        // Will implement fault behavior later
        LOG_DEBUG("Fault would be triggered for utimens: %s", path);
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
    .open     = fs_fault_open,
    .read     = fs_fault_read,
    .write    = fs_fault_write,
    .release  = fs_fault_release,
    .create   = fs_fault_create,
    .chmod    = fs_fault_chmod,
    .chown    = fs_fault_chown,
    .truncate = fs_fault_truncate,
    .utimens  = fs_fault_utimens,
};

// FUSE option processing function
static int fs_fault_opt_proc(void *data, const char *arg, int key, struct fuse_args *outargs) {
    struct fs_fault_config *cfg = (struct fs_fault_config*)data;
    
    (void)outargs; // Mark parameter as unused to fix warning
    
    if (key == FUSE_OPT_KEY_NONOPT && !cfg->storage_path && arg[0] != '-') {
        // First non-option argument is the mount point, ignore it
        return 1;
    }
    
    return 1;  // Keep all other arguments
}

// FUSE option specification
static struct fuse_opt fs_fault_opts[] = {
    {"--storage=%s", offsetof(struct fs_fault_config, storage_path), 0},
    {"--log=%s", offsetof(struct fs_fault_config, log_file), 0},
    {"--loglevel=%d", offsetof(struct fs_fault_config, log_level), 0},
    FUSE_OPT_END
};

int main(int argc, char *argv[]) {
    int ret;
    struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
    
    // Set default config values
    memset(&config, 0, sizeof(config));
    config.storage_path = strdup(default_storage_path);
    config.log_file = strdup("stdout");
    config.log_level = LOG_INFO;
    
    // Parse command line options
    if (fuse_opt_parse(&args, &config, fs_fault_opts, fs_fault_opt_proc) == -1) {
        return 1;
    }
    
    // Initialize logging
    log_init(config.log_file, config.log_level);
    LOG_INFO("Filesystem Fault Injector initializing...");
    LOG_INFO("Using storage path: %s", config.storage_path);
    
    // Create storage directory if it doesn't exist
    mkdir(config.storage_path, 0755);
    
    // Initialize filesystem operations
    fs_ops_init(config.storage_path);
    
    // Initialize fault injector
    fault_injector_init();
    
    // Run FUSE main loop
    ret = fuse_main(args.argc, args.argv, &fs_fault_oper, NULL);
    
    // Clean up resources
    fs_ops_cleanup();
    fault_injector_cleanup();
    log_close();
    
    // Free config strings
    free(config.storage_path);
    free(config.log_file);
    fuse_opt_free_args(&args);
    
    return ret;
}