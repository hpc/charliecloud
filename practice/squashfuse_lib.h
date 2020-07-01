#ifndef _SQUASHFUSE_LIB_H_
#define _SQUASHFUSE_LIB_H_

struct sqfs_hl {
	sqfs fs;
	sqfs_inode root;
};
typedef struct sqfs_hl sqfs_hl;

extern static sqfs_err sqfs_hl_lookup(sqfs **fs, sqfs_inode *inode,
		const char *path);
extern static void sqfs_hl_op_destroy(void *user_data);

extern static void *sqfs_hl_op_init(struct fuse_conn_info *conn
#if FUSE_USE_VERSION >= 30
			     ,struct fuse_config *cfg
#endif
			     ) ;

extern static int sqfs_hl_op_getattr(const char *path, struct stat *st
#if FUSE_USE_VERSION >= 30
			      , struct fuse_file_info *fi
#endif
			      );

extern static int sqfs_hl_op_opendir(const char *path, struct fuse_file_info *fi);

extern static int sqfs_hl_op_releasedir(const char *path,
		struct fuse_file_info *fi);

extern static int sqfs_hl_op_readdir(const char *path, void *buf,
		fuse_fill_dir_t filler, off_t offset, struct fuse_file_info *fi
#if FUSE_USE_VERSION >= 30
	,enum fuse_readdir_flags flags
#endif
	) ;


extern static int sqfs_hl_op_open(const char *path, struct fuse_file_info *fi);

extern static int sqfs_hl_op_create(const char* unused_path, mode_t unused_mode,
		struct fuse_file_info *unused_fi) ;

extern static int sqfs_hl_op_release(const char *path, struct fuse_file_info *fi) {
	free((sqfs_inode*)(intptr_t)fi->fh);

extern static int sqfs_hl_op_read(const char *path, char *buf, size_t size,
		off_t off, struct fuse_file_info *fi) ;

extern static int sqfs_hl_op_readlink(const char *path, char *buf, size_t size);

extern static int sqfs_hl_op_listxattr(const char *path, char *buf, size_t size);

extern static int sqfs_hl_op_getxattr(const char *path, const char *name,
		char *value, size_t size
#ifdef FUSE_XATTR_POSITION
		, uint32_t position
#endif
		);

extern static int sqfs_hl_op_statfs(const char *path, struct statvfs *st);

extern static sqfs_hl *sqfs_hl_open(const char *path, size_t offset);
#endif
