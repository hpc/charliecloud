#include <fuse.h>

/**
 * takes the directory to unmount and unmounts it
 */
static void *hello_init(struct fuse_conn_info *conn,
                        struct fuse_config *cfg)
{
        (void) conn;
        cfg->kernel_cache = 1;
        return NULL;
}
static int hello_getattr(const char *path, struct stat *stbuf,
                         struct fuse_file_info *fi)
{
        (void) fi;
        int res = 0;
        memset(stbuf, 0, sizeof(struct stat));
        if (strcmp(path, "/") == 0) {
                stbuf->st_mode = S_IFDIR | 0755;
                stbuf->st_nlink = 2;
        } else if (strcmp(path+1, options.filename) == 0) {
                stbuf->st_mode = S_IFREG | 0444;
                stbuf->st_nlink = 1;
                stbuf->st_size = strlen(options.contents);
        } else
                res = -ENOENT;
        return res;
}
static int hello_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                         off_t offset, struct fuse_file_info *fi,
                         enum fuse_readdir_flags flags)
{
        (void) offset;
        (void) fi;
        (void) flags;
        if (strcmp(path, "/") != 0)
                return -ENOENT;
        filler(buf, ".", NULL, 0, 0);
        filler(buf, "..", NULL, 0, 0);
        filler(buf, options.filename, NULL, 0, 0);
        return 0;
}
static int hello_open(const char *path, struct fuse_file_info *fi)
{
        if (strcmp(path+1, options.filename) != 0)
                return -ENOENT;
        if ((fi->flags & O_ACCMODE) != O_RDONLY)
                return -EACCES;
        return 0;
}
static int hello_read(const char *path, char *buf, size_t size, off_t offset,
                      struct fuse_file_info *fi)
{
        size_t len;
        (void) fi;
        if(strcmp(path+1, options.filename) != 0)
                return -ENOENT;
        len = strlen(options.contents);
        if (offset < len) {
                if (offset + size > len)
                        size = len - offset;
                memcpy(buf, options.contents + offset, size);
        } else
                size = 0;
        return size;
}
static const struct fuse_operations hello_oper = {
        .init           = hello_init,
        .getattr        = hello_getattr,
        .readdir        = hello_readdir,
        .open           = hello_open,
        .read           = hello_read,
};

int main(int argc, char *argv[]){
  int ret = 1;
  struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
  struct fuse *fuse;
  struct fuse_cmdline_opts opts;
  size_t op_size;
  void *user_data;
  fuse = fuse_new(&args, hello_oper, op_size, NULL);
  fuse_unmount(fuse);
  return ret; 
}
