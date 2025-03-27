#ifndef FS_OPERATIONS_H
#define FS_OPERATIONS_H

#include <fuse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <limits.h>
#include <sys/types.h>
#include <time.h>  /* For struct timespec */

// Initialize the filesystem operations
void fs_ops_init(const char *storage_dir);

// Clean up filesystem operations
void fs_ops_cleanup(void);

// Filesystem operations
int fs_op_getattr(const char *path, struct stat *stbuf);
int fs_op_readdir(const char *path, void *buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info *fi);
int fs_op_create(const char *path, mode_t mode, struct fuse_file_info *fi);
int fs_op_mknod(const char *path, mode_t mode, dev_t rdev);
int fs_op_read(const char *path, char *buf, size_t size, off_t offset, struct fuse_file_info *fi);
int fs_op_write(const char *path, const char *buf, size_t size, off_t offset, struct fuse_file_info *fi);
int fs_op_open(const char *path, struct fuse_file_info *fi);
int fs_op_release(const char *path, struct fuse_file_info *fi);
int fs_op_mkdir(const char *path, mode_t mode);
int fs_op_rmdir(const char *path);
int fs_op_unlink(const char *path);
int fs_op_chmod(const char *path, mode_t mode);
int fs_op_chown(const char *path, uid_t uid, gid_t gid);
int fs_op_truncate(const char *path, off_t size);
int fs_op_utimens(const char *path, const struct timespec ts[2]);

// Helper functions
char* get_full_path(const char *path);

#endif // FS_OPERATIONS_H