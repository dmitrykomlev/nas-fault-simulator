#include "fs_operations.h"
#include "log.h"
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/time.h>
#include <utime.h>
#include <sys/types.h>

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

// Implementation of filesystem operations

int fs_op_getattr(const char *path, struct stat *stbuf) {
    LOG_DEBUG("getattr: %s", path);
    
    int res = 0;
    char *fullpath = get_full_path(path);
    
    if (!fullpath) return -ENOMEM;
    
    memset(stbuf, 0, sizeof(struct stat));
    
    res = lstat(fullpath, stbuf);
    free(fullpath);
    
    if (res == -1) {
        res = -errno;
        LOG_DEBUG("getattr failed: %s, error: %s", path, strerror(errno));
        return res;
    }
    
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
    
    int fd;
    char *fullpath = get_full_path(path);
    
    if (!fullpath) return -ENOMEM;
    
    fd = creat(fullpath, mode);
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
    
    int fd;
    int res;
    
    if (fi == NULL) {
        char *fullpath = get_full_path(path);
        if (!fullpath) return -ENOMEM;
        
        fd = open(fullpath, O_WRONLY);
        free(fullpath);
        
        if (fd == -1) {
            int err = -errno;
            LOG_DEBUG("write failed to open: %s, error: %s", path, strerror(errno));
            return err;
        }
    } else {
        fd = fi->fh;
    }
    
    res = pwrite(fd, buf, size, offset);
    if (res == -1) {
        res = -errno;
        LOG_DEBUG("write failed: %s, error: %s", path, strerror(errno));
    }
    
    if (fi == NULL) {
        close(fd);
    }
    
    return res;
}

int fs_op_open(const char *path, struct fuse_file_info *fi) {
    LOG_DEBUG("open: %s, flags: 0x%x", path, fi->flags);
    
    int fd;
    char *fullpath = get_full_path(path);
    
    if (!fullpath) return -ENOMEM;
    
    fd = open(fullpath, fi->flags);
    free(fullpath);
    
    if (fd == -1) {
        int err = -errno;
        LOG_DEBUG("open failed: %s, error: %s", path, strerror(errno));
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
    
    int res;
    char *fullpath = get_full_path(path);
    
    if (!fullpath) return -ENOMEM;
    
    res = mkdir(fullpath, mode);
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
    
    int res;
    char *fullpath = get_full_path(path);
    
    if (!fullpath) return -ENOMEM;
    
    res = rmdir(fullpath);
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
    
    int res;
    char *fullpath = get_full_path(path);
    
    if (!fullpath) return -ENOMEM;
    
    res = unlink(fullpath);
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
    
    int res;
    char *fullpath = get_full_path(path);
    
    if (!fullpath) return -ENOMEM;
    
    res = chmod(fullpath, mode);
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
    
    int res;
    char *fullpath = get_full_path(path);
    
    if (!fullpath) return -ENOMEM;
    
    res = chown(fullpath, uid, gid);
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
    
    int res;
    char *fullpath = get_full_path(path);
    
    if (!fullpath) return -ENOMEM;
    
    res = truncate(fullpath, size);
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
    
    int res;
    char *fullpath = get_full_path(path);
    
    if (!fullpath) return -ENOMEM;
    
    // FUSE passes timestamps in ts[0] (access) and ts[1] (modification)
    // Convert to a format usable by utimes()
    struct timeval tv[2];
    tv[0].tv_sec = ts[0].tv_sec;
    tv[0].tv_usec = ts[0].tv_nsec / 1000;
    tv[1].tv_sec = ts[1].tv_sec;
    tv[1].tv_usec = ts[1].tv_nsec / 1000;
    
    res = utimes(fullpath, tv);
    
    free(fullpath);
    
    if (res == -1) {
        int err = -errno;
        LOG_DEBUG("utimens failed: %s, error: %s", path, strerror(errno));
        return err;
    }
    
    return 0;
}