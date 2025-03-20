#define FUSE_USE_VERSION 26

#include <fuse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <limits.h>

static const char *storage_path = "/tmp/fs_fault_storage";

// Basic FUSE operations

static int fs_fault_getattr(const char *path, struct stat *stbuf)
{
    int res = 0;
    char fullpath[PATH_MAX];
    
    memset(stbuf, 0, sizeof(struct stat));
    
    sprintf(fullpath, "%s%s", storage_path, path);
    
    res = lstat(fullpath, stbuf);
    if (res == -1)
        return -errno;
    
    return 0;
}

static int fs_fault_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                           off_t offset, struct fuse_file_info *fi)
{
    DIR *dp;
    struct dirent *de;
    char fullpath[PATH_MAX];
    
    sprintf(fullpath, "%s%s", storage_path, path);
    
    dp = opendir(fullpath);
    if (dp == NULL)
        return -errno;
    
    while ((de = readdir(dp)) != NULL) {
        struct stat st;
        memset(&st, 0, sizeof(st));
        st.st_ino = de->d_ino;
        st.st_mode = de->d_type << 12;
        
        if (filler(buf, de->d_name, &st, 0))
            break;
    }
    
    closedir(dp);
    return 0;
}

// Add create operation
static int fs_fault_create(const char *path, mode_t mode, struct fuse_file_info *fi)
{
    int fd;
    char fullpath[PATH_MAX];
    
    sprintf(fullpath, "%s%s", storage_path, path);
    
    fd = creat(fullpath, mode);
    if (fd == -1)
        return -errno;
    
    fi->fh = fd;
    return 0;
}

// Add mknod operation (necessary for some file creation scenarios)
static int fs_fault_mknod(const char *path, mode_t mode, dev_t rdev)
{
    int res;
    char fullpath[PATH_MAX];
    
    sprintf(fullpath, "%s%s", storage_path, path);
    
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
    
    if (res == -1)
        return -errno;
    
    return 0;
}

// Add basic read operation
static int fs_fault_read(const char *path, char *buf, size_t size, off_t offset,
                        struct fuse_file_info *fi)
{
    int fd;
    int res;
    char fullpath[PATH_MAX];
    
    if (fi == NULL) {
        sprintf(fullpath, "%s%s", storage_path, path);
        fd = open(fullpath, O_RDONLY);
    } else {
        fd = fi->fh;
    }
    
    if (fd == -1)
        return -errno;
    
    res = pread(fd, buf, size, offset);
    if (res == -1)
        res = -errno;
    
    if (fi == NULL)
        close(fd);
    
    return res;
}

// Add basic write operation
static int fs_fault_write(const char *path, const char *buf, size_t size,
                         off_t offset, struct fuse_file_info *fi)
{
    int fd;
    int res;
    char fullpath[PATH_MAX];
    
    if (fi == NULL) {
        sprintf(fullpath, "%s%s", storage_path, path);
        fd = open(fullpath, O_WRONLY);
    } else {
        fd = fi->fh;
    }
    
    if (fd == -1)
        return -errno;
    
    res = pwrite(fd, buf, size, offset);
    if (res == -1)
        res = -errno;
    
    if (fi == NULL)
        close(fd);
    
    return res;
}

// Add basic open operation
static int fs_fault_open(const char *path, struct fuse_file_info *fi)
{
    int fd;
    char fullpath[PATH_MAX];
    
    sprintf(fullpath, "%s%s", storage_path, path);
    
    fd = open(fullpath, fi->flags);
    if (fd == -1)
        return -errno;
    
    fi->fh = fd;
    return 0;
}

// Add release operation (close file)
static int fs_fault_release(const char *path, struct fuse_file_info *fi)
{
    (void) path;
    
    if (close(fi->fh) == -1)
        return -errno;
    
    return 0;
}

// Add basic mkdir operation
static int fs_fault_mkdir(const char *path, mode_t mode)
{
    int res;
    char fullpath[PATH_MAX];
    
    sprintf(fullpath, "%s%s", storage_path, path);
    
    res = mkdir(fullpath, mode);
    if (res == -1)
        return -errno;
    
    return 0;
}

// Add rmdir operation
static int fs_fault_rmdir(const char *path)
{
    int res;
    char fullpath[PATH_MAX];
    
    sprintf(fullpath, "%s%s", storage_path, path);
    
    res = rmdir(fullpath);
    if (res == -1)
        return -errno;
    
    return 0;
}

// Add unlink operation (delete file)
static int fs_fault_unlink(const char *path)
{
    int res;
    char fullpath[PATH_MAX];
    
    sprintf(fullpath, "%s%s", storage_path, path);
    
    res = unlink(fullpath);
    if (res == -1)
        return -errno;
    
    return 0;
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
};

int main(int argc, char *argv[])
{
    // Create storage directory if it doesn't exist
    mkdir(storage_path, 0755);
    
    printf("Filesystem Fault Injector initializing...\n");
    printf("Using storage path: %s\n", storage_path);
    
    // Run FUSE main loop
    return fuse_main(argc, argv, &fs_fault_oper, NULL);
}