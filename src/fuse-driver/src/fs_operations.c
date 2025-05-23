#include "fs_operations.h"
#include "log.h"
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/time.h>
#include <utime.h>
#include <sys/types.h>
#include <unistd.h>

// Static storage path variable
static char *storage_path = NULL;

// Initialize storage path
void fs_ops_init(const char *storage_dir) {
    if (storage_dir) {
        storage_path = strdup(storage_dir);
        LOG_INFO("Filesystem operations initialized with storage path: %s", storage_path);
        
        // Create storage directory if it doesn't exist
        mkdir(storage_path, 0755);
    } else {
        LOG_ERROR("Invalid storage directory provided");
    }
}

// Clean up resources
void fs_ops_cleanup(void) {
    if (storage_path) {
        free(storage_path);
        storage_path = NULL;
    }
}

// Helper function to build full paths
char* get_full_path(const char *path) {
    if (!storage_path) {
        LOG_ERROR("Storage path not initialized");
        return NULL;
    }
    
    char *fullpath = malloc(PATH_MAX);
    if (!fullpath) {
        LOG_ERROR("Memory allocation failed for path: %s", path);
        return NULL;
    }
    
    sprintf(fullpath, "%s%s", storage_path, path);
    return fullpath;
}

// Helper function to check permissions
static int check_file_perms(const char *path, int mode) {
    char *fullpath = get_full_path(path);
    if (!fullpath) return -ENOMEM;
    
    struct stat stbuf;
    int ret = lstat(fullpath, &stbuf);
    
    if (ret == -1) {
        ret = -errno;
        free(fullpath);
        return ret;
    }
    
    // Check owner permissions (we only care about the owner in this simplified model)
    if ((mode & R_OK) && !(stbuf.st_mode & S_IRUSR)) {
        LOG_DEBUG("Permission check failed: no read permission for %s", path);
        free(fullpath);
        return -EACCES;
    }
    
    if ((mode & W_OK) && !(stbuf.st_mode & S_IWUSR)) {
        LOG_DEBUG("Permission check failed: no write permission for %s", path);
        free(fullpath);
        return -EACCES;
    }
    
    if ((mode & X_OK) && !(stbuf.st_mode & S_IXUSR)) {
        LOG_DEBUG("Permission check failed: no execute permission for %s", path);
        free(fullpath);
        return -EACCES;
    }
    
    free(fullpath);
    return 0;
}

// Implementation of filesystem operations

int fs_op_getattr(const char *path, struct stat *stbuf) {
    LOG_DEBUG("getattr: %s", path);
    LOG_DEBUG("GETATTR_STEP_1: Starting getattr operation for %s", path);
    
    int res = 0;
    LOG_DEBUG("GETATTR_STEP_2: Getting full path for %s", path);
    char *fullpath = get_full_path(path);
    
    if (!fullpath) {
        LOG_DEBUG("GETATTR_STEP_3: Failed to get full path for %s", path);
        return -ENOMEM;
    }
    
    LOG_DEBUG("GETATTR_STEP_4: Full path is %s, initializing stat buffer", fullpath);
    memset(stbuf, 0, sizeof(struct stat));
    
    LOG_DEBUG("GETATTR_STEP_5: About to call lstat() for %s", fullpath);
    res = lstat(fullpath, stbuf);
    LOG_DEBUG("GETATTR_STEP_6: lstat() returned %d for %s", res, fullpath);
    
    LOG_DEBUG("GETATTR_STEP_7: Freeing fullpath for %s", path);
    free(fullpath);
    
    if (res == -1) {
        res = -errno;
        LOG_DEBUG("GETATTR_STEP_8: lstat failed for %s, errno=%d (%s)", path, -res, strerror(errno));
        LOG_DEBUG("getattr failed: %s, error: %s", path, strerror(errno));
        return res;
    }
    
    LOG_DEBUG("GETATTR_STEP_9: getattr operation complete for %s, returning success", path);
    return 0;
}

int fs_op_readdir(const char *path, void *buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info *fi) {
    LOG_DEBUG("readdir: %s", path);
    
    // Mark unused parameters
    (void)offset;
    (void)fi;
    
    DIR *dp;
    struct dirent *de;
    char *fullpath = get_full_path(path);
    
    if (!fullpath) return -ENOMEM;
    
    // Check read permission
    int perms = check_file_perms(path, R_OK | X_OK);
    if (perms != 0) {
        free(fullpath);
        return perms;
    }
    
    dp = opendir(fullpath);
    free(fullpath);
    
    if (dp == NULL) {
        int err = -errno;
        LOG_DEBUG("readdir failed to open: %s, error: %s", path, strerror(errno));
        return err;
    }
    
    while ((de = readdir(dp)) != NULL) {
        struct stat st;
        memset(&st, 0, sizeof(st));
        st.st_ino = de->d_ino;
        st.st_mode = de->d_type << 12;
        
        if (filler(buf, de->d_name, &st, 0)) {
            LOG_DEBUG("readdir: buffer full for %s", path);
            break;
        }
    }
    
    closedir(dp);
    return 0;
}

int fs_op_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    LOG_DEBUG("create: %s, mode: %o", path, mode);
    
    // Check if file exists, and if so, check for write permission
    struct stat stbuf;
    char *fullpath = get_full_path(path);
    if (!fullpath) return -ENOMEM;
    
    if (lstat(fullpath, &stbuf) == 0) {
        // File exists, check write permission
        int perms = check_file_perms(path, W_OK);
        if (perms != 0) {
            LOG_DEBUG("create denied: %s already exists and no write permission", path);
            free(fullpath);
            return perms;
        }
    }
    
    int fd = creat(fullpath, mode);
    free(fullpath);
    
    if (fd == -1) {
        int err = -errno;
        LOG_DEBUG("create failed: %s, error: %s", path, strerror(errno));
        return err;
    }
    
    fi->fh = fd;
    return 0;
}

int fs_op_mknod(const char *path, mode_t mode, dev_t rdev) {
    LOG_DEBUG("mknod: %s, mode: %o", path, mode);
    
    int res;
    char *fullpath = get_full_path(path);
    
    if (!fullpath) return -ENOMEM;
    
    // If file exists, check write access to directory
    char *dirpath = strdup(path);
    char *last_slash = strrchr(dirpath, '/');
    if (last_slash) {
        *last_slash = '\0';
        if (*dirpath == '\0') {
            strcpy(dirpath, "/");
        }
    } else {
        strcpy(dirpath, "/");
    }
    
    int perms = check_file_perms(dirpath, W_OK);
    free(dirpath);
    
    if (perms != 0) {
        LOG_DEBUG("mknod denied: no write permission to directory for %s", path);
        free(fullpath);
        return perms;
    }
    
    // If it's a regular file
    if (S_ISREG(mode)) {
        res = open(fullpath, O_CREAT | O_EXCL | O_WRONLY, mode);
        if (res >= 0)
            res = close(res);
    } else if (S_ISFIFO(mode)) {
        res = mkfifo(fullpath, mode);
    } else {
        res = mknod(fullpath, mode, rdev);
    }
    
    free(fullpath);
    
    if (res == -1) {
        int err = -errno;
        LOG_DEBUG("mknod failed: %s, error: %s", path, strerror(errno));
        return err;
    }
    
    return 0;
}

int fs_op_read(const char *path, char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    LOG_DEBUG("read: %s, size: %zu, offset: %ld", path, size, offset);
    
    int fd;
    int res;
    
    if (fi == NULL) {
        // No file handle provided, check read permission
        int perms = check_file_perms(path, R_OK);
        if (perms != 0) {
            LOG_DEBUG("read denied: no read permission for %s", path);
            return perms;
        }
        
        char *fullpath = get_full_path(path);
        if (!fullpath) return -ENOMEM;
        
        fd = open(fullpath, O_RDONLY);
        free(fullpath);
        
        if (fd == -1) {
            int err = -errno;
            LOG_DEBUG("read failed to open: %s, error: %s", path, strerror(errno));
            return err;
        }
    } else {
        fd = fi->fh;
    }
    
    res = pread(fd, buf, size, offset);
    if (res == -1) {
        res = -errno;
        LOG_DEBUG("read failed: %s, error: %s", path, strerror(errno));
    }
    
    if (fi == NULL) {
        close(fd);
    }
    
    return res;
}

int fs_op_write(const char *path, const char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    LOG_DEBUG("write: %s, size: %zu, offset: %ld", path, size, offset);
    LOG_DEBUG("WRITE_STEP_1: Starting write operation for %s", path);
    
    int fd;
    int res;
    
    LOG_DEBUG("WRITE_STEP_2: Checking file handle for %s (fi=%p)", path, fi);
    if (fi == NULL) {
        LOG_DEBUG("WRITE_STEP_3a: No file handle, checking permissions for %s", path);
        // No file handle provided, check write permission
        int perms = check_file_perms(path, W_OK);
        if (perms != 0) {
            LOG_DEBUG("write denied: no write permission for %s", path);
            return perms;
        }
        LOG_DEBUG("WRITE_STEP_4a: Permissions OK, getting full path for %s", path);
        
        char *fullpath = get_full_path(path);
        if (!fullpath) return -ENOMEM;
        LOG_DEBUG("WRITE_STEP_5a: Full path: %s, calling open()", fullpath);
        
        fd = open(fullpath, O_WRONLY);
        LOG_DEBUG("WRITE_STEP_6a: open() returned fd=%d for %s", fd, path);
        free(fullpath);
        
        if (fd == -1) {
            int err = -errno;
            LOG_DEBUG("write failed to open: %s, error: %s", path, strerror(errno));
            return err;
        }
    } else {
        LOG_DEBUG("WRITE_STEP_3b: Using existing file handle fd=%d for %s", (int)fi->fh, path);
        fd = fi->fh;
    }
    
    LOG_DEBUG("WRITE_STEP_7: About to call pwrite() for %s (fd=%d, size=%zu, offset=%ld)", path, fd, size, offset);
    res = pwrite(fd, buf, size, offset);
    LOG_DEBUG("WRITE_STEP_8: pwrite() returned %d for %s", res, path);
    
    if (res == -1) {
        res = -errno;
        LOG_DEBUG("write failed: %s, error: %s", path, strerror(errno));
    }
    
    LOG_DEBUG("WRITE_STEP_9: Checking if need to close fd for %s (fi=%p)", path, fi);
    if (fi == NULL) {
        LOG_DEBUG("WRITE_STEP_10a: Closing fd=%d for %s", fd, path);
        close(fd);
        LOG_DEBUG("WRITE_STEP_11a: Closed fd for %s", path);
    } else {
        LOG_DEBUG("WRITE_STEP_10b: Not closing fd (using file handle) for %s", path);
    }
    
    LOG_DEBUG("WRITE_STEP_12: Write operation complete for %s, returning %d", path, res);
    return res;
}

int fs_op_open(const char *path, struct fuse_file_info *fi) {
    LOG_DEBUG("open: %s, flags: 0x%x", path, fi->flags);
    
    // Check permissions based on requested flags
    if ((fi->flags & O_ACCMODE) == O_RDONLY) {
        int perms = check_file_perms(path, R_OK);
        if (perms != 0) {
            LOG_DEBUG("open denied: no read permission for %s", path);
            return perms;
        }
    } else if ((fi->flags & O_ACCMODE) == O_WRONLY) {
        int perms = check_file_perms(path, W_OK);
        if (perms != 0) {
            LOG_DEBUG("open denied: no write permission for %s", path);
            return perms;
        }
    } else if ((fi->flags & O_ACCMODE) == O_RDWR) {
        int perms = check_file_perms(path, R_OK | W_OK);
        if (perms != 0) {
            LOG_DEBUG("open denied: no read/write permission for %s", path);
            return perms;
        }
    }
    
    char *fullpath = get_full_path(path);
    if (!fullpath) return -ENOMEM;
    
    int fd = open(fullpath, fi->flags);
    free(fullpath);
    
    if (fd == -1) {
        int err = -errno;
        LOG_DEBUG("open failed: %s, flags: 0x%x, error: %s", path, fi->flags, strerror(errno));
        return err;
    }
    
    fi->fh = fd;
    return 0;
}

int fs_op_release(const char *path, struct fuse_file_info *fi) {
    LOG_DEBUG("release: %s", path);
    
    if (close(fi->fh) == -1) {
        int err = -errno;
        LOG_DEBUG("release failed: %s, error: %s", path, strerror(errno));
        return err;
    }
    
    return 0;
}

int fs_op_mkdir(const char *path, mode_t mode) {
    LOG_DEBUG("mkdir: %s, mode: %o", path, mode);
    
    // Check write permission on parent directory
    char *dirpath = strdup(path);
    char *last_slash = strrchr(dirpath, '/');
    if (last_slash) {
        *last_slash = '\0';
        if (*dirpath == '\0') {
            strcpy(dirpath, "/");
        }
    } else {
        strcpy(dirpath, "/");
    }
    
    int perms = check_file_perms(dirpath, W_OK);
    free(dirpath);
    
    if (perms != 0) {
        LOG_DEBUG("mkdir denied: no write permission to parent directory for %s", path);
        return perms;
    }
    
    char *fullpath = get_full_path(path);
    if (!fullpath) return -ENOMEM;
    
    int res = mkdir(fullpath, mode);
    free(fullpath);
    
    if (res == -1) {
        int err = -errno;
        LOG_DEBUG("mkdir failed: %s, error: %s", path, strerror(errno));
        return err;
    }
    
    return 0;
}

int fs_op_rmdir(const char *path) {
    LOG_DEBUG("rmdir: %s", path);
    
    // Check write permission on parent directory
    char *dirpath = strdup(path);
    char *last_slash = strrchr(dirpath, '/');
    if (last_slash) {
        *last_slash = '\0';
        if (*dirpath == '\0') {
            strcpy(dirpath, "/");
        }
    } else {
        strcpy(dirpath, "/");
    }
    
    int perms = check_file_perms(dirpath, W_OK);
    free(dirpath);
    
    if (perms != 0) {
        LOG_DEBUG("rmdir denied: no write permission to parent directory for %s", path);
        return perms;
    }
    
    char *fullpath = get_full_path(path);
    if (!fullpath) return -ENOMEM;
    
    int res = rmdir(fullpath);
    free(fullpath);
    
    if (res == -1) {
        int err = -errno;
        LOG_DEBUG("rmdir failed: %s, error: %s", path, strerror(errno));
        return err;
    }
    
    return 0;
}

int fs_op_unlink(const char *path) {
    LOG_DEBUG("unlink: %s", path);
    
    // Check write permission on parent directory
    char *dirpath = strdup(path);
    char *last_slash = strrchr(dirpath, '/');
    if (last_slash) {
        *last_slash = '\0';
        if (*dirpath == '\0') {
            strcpy(dirpath, "/");
        }
    } else {
        strcpy(dirpath, "/");
    }
    
    int perms = check_file_perms(dirpath, W_OK);
    free(dirpath);
    
    if (perms != 0) {
        LOG_DEBUG("unlink denied: no write permission to parent directory for %s", path);
        return perms;
    }
    
    char *fullpath = get_full_path(path);
    if (!fullpath) return -ENOMEM;
    
    int res = unlink(fullpath);
    free(fullpath);
    
    if (res == -1) {
        int err = -errno;
        LOG_DEBUG("unlink failed: %s, error: %s", path, strerror(errno));
        return err;
    }
    
    return 0;
}

int fs_op_chmod(const char *path, mode_t mode) {
    LOG_DEBUG("chmod: %s, mode: %o", path, mode);
    
    // Check write permission to the file
    int perms = check_file_perms(path, W_OK);
    if (perms != 0) {
        LOG_DEBUG("chmod denied: no write permission for %s", path);
        return perms;
    }
    
    char *fullpath = get_full_path(path);
    if (!fullpath) return -ENOMEM;
    
    int res = chmod(fullpath, mode);
    free(fullpath);
    
    if (res == -1) {
        int err = -errno;
        LOG_DEBUG("chmod failed: %s, error: %s", path, strerror(errno));
        return err;
    }
    
    return 0;
}

int fs_op_chown(const char *path, uid_t uid, gid_t gid) {
    LOG_DEBUG("chown: %s, uid: %d, gid: %d", path, uid, gid);
    
    // Check write permission to the file
    int perms = check_file_perms(path, W_OK);
    if (perms != 0) {
        LOG_DEBUG("chown denied: no write permission for %s", path);
        return perms;
    }
    
    char *fullpath = get_full_path(path);
    if (!fullpath) return -ENOMEM;
    
    int res = chown(fullpath, uid, gid);
    free(fullpath);
    
    if (res == -1) {
        int err = -errno;
        LOG_DEBUG("chown failed: %s, error: %s", path, strerror(errno));
        return err;
    }
    
    return 0;
}

int fs_op_truncate(const char *path, off_t size) {
    LOG_DEBUG("truncate: %s, size: %ld", path, size);
    
    // Check write permission
    int perms = check_file_perms(path, W_OK);
    if (perms != 0) {
        LOG_DEBUG("truncate denied: no write permission for %s", path);
        return perms;
    }
    
    char *fullpath = get_full_path(path);
    if (!fullpath) return -ENOMEM;
    
    int res = truncate(fullpath, size);
    free(fullpath);
    
    if (res == -1) {
        int err = -errno;
        LOG_DEBUG("truncate failed: %s, error: %s", path, strerror(errno));
        return err;
    }
    
    return 0;
}

int fs_op_utimens(const char *path, const struct timespec ts[2]) {
    LOG_DEBUG("utimens: %s", path);
    
    // Check write permission
    int perms = check_file_perms(path, W_OK);
    if (perms != 0) {
        LOG_DEBUG("utimens denied: no write permission for %s", path);
        return perms;
    }
    
    char *fullpath = get_full_path(path);
    if (!fullpath) return -ENOMEM;
    
    // FUSE passes timestamps in ts[0] (access) and ts[1] (modification)
    // Convert to a format usable by utimes()
    struct timeval tv[2];
    tv[0].tv_sec = ts[0].tv_sec;
    tv[0].tv_usec = ts[0].tv_nsec / 1000;
    tv[1].tv_sec = ts[1].tv_sec;
    tv[1].tv_usec = ts[1].tv_nsec / 1000;
    
    int res = utimes(fullpath, tv);
    
    free(fullpath);
    
    if (res == -1) {
        int err = -errno;
        LOG_DEBUG("utimens failed: %s, error: %s", path, strerror(errno));
        return err;
    }
    
    return 0;
}

int fs_op_rename(const char *path, const char *newpath) {
    LOG_DEBUG("rename: %s to %s", path, newpath);
    
    // Check write permission on both files if they exist
    // and on both parent directories
    
    // Source file permissions
    int perms = check_file_perms(path, W_OK);
    if (perms != 0) {
        LOG_DEBUG("rename denied: no write permission for source %s", path);
        return perms;
    }
    
    // Source directory permissions
    char *dirpath = strdup(path);
    char *last_slash = strrchr(dirpath, '/');
    if (last_slash) {
        *last_slash = '\0';
        if (*dirpath == '\0') {
            strcpy(dirpath, "/");
        }
    } else {
        strcpy(dirpath, "/");
    }
    
    perms = check_file_perms(dirpath, W_OK);
    free(dirpath);
    
    if (perms != 0) {
        LOG_DEBUG("rename denied: no write permission to source directory for %s", path);
        return perms;
    }
    
    // Destination directory permissions
    dirpath = strdup(newpath);
    last_slash = strrchr(dirpath, '/');
    if (last_slash) {
        *last_slash = '\0';
        if (*dirpath == '\0') {
            strcpy(dirpath, "/");
        }
    } else {
        strcpy(dirpath, "/");
    }
    
    perms = check_file_perms(dirpath, W_OK);
    free(dirpath);
    
    if (perms != 0) {
        LOG_DEBUG("rename denied: no write permission to destination directory for %s", newpath);
        return perms;
    }
    
    // If destination file exists, check write permission
    struct stat stbuf;
    if (fs_op_getattr(newpath, &stbuf) == 0) {
        perms = check_file_perms(newpath, W_OK);
        if (perms != 0) {
            LOG_DEBUG("rename denied: no write permission for destination %s", newpath);
            return perms;
        }
    }
    
    char *fullpath = get_full_path(path);
    if (!fullpath) return -ENOMEM;
    
    char *fullnewpath = get_full_path(newpath);
    if (!fullnewpath) {
        free(fullpath);
        return -ENOMEM;
    }
    
    int res = rename(fullpath, fullnewpath);
    
    free(fullpath);
    free(fullnewpath);
    
    if (res == -1) {
        res = -errno;
        LOG_DEBUG("rename failed: %s to %s, error: %s", path, newpath, strerror(errno));
    }
    
    return res;
}

int fs_op_access(const char *path, int mode) {
    LOG_DEBUG("access: %s, mode: %d", path, mode);
    
    return check_file_perms(path, mode);
}