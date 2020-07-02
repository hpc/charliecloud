#include "squashfuse.h"
#include "fuseprivate.h"
//#include <stat.h>
#include "nonstd.h"
//#include "squashfuse_lib.h"

#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


int main(int argc, char *argv[]) {
	struct fuse_args args;
	sqfs_opts opts;
	sqfs_hl *hl;
	int ret;
	
	struct fuse_opt fuse_opts[] = {
		{"offset=%zu", offsetof(sqfs_opts, offset), 0},
		FUSE_OPT_END
	};

	struct fuse_operations sqfs_hl_ops;
	memset(&sqfs_hl_ops, 0, sizeof(sqfs_hl_ops));
	sqfs_hl_ops.init			= sqfs_hl_op_init;
	sqfs_hl_ops.destroy		= sqfs_hl_op_destroy;
/*	sqfs_hl_ops.getattr		= sqfs_hl_op_getattr;
	sqfs_hl_ops.opendir		= sqfs_hl_op_opendir;
	sqfs_hl_ops.releasedir	= sqfs_hl_op_releasedir;
	sqfs_hl_ops.readdir		= sqfs_hl_op_readdir;
	sqfs_hl_ops.open		= sqfs_hl_op_open;
	sqfs_hl_ops.create		= sqfs_hl_op_create;
	sqfs_hl_ops.release		= sqfs_hl_op_release;
	sqfs_hl_ops.read		= sqfs_hl_op_read;
	sqfs_hl_ops.readlink	= sqfs_hl_op_readlink;
	sqfs_hl_ops.listxattr	= sqfs_hl_op_listxattr;
	sqfs_hl_ops.getxattr	= sqfs_hl_op_getxattr;
	sqfs_hl_ops.statfs    = sqfs_hl_op_statfs;
  
	args.argc = argc;
	args.argv = argv;
	args.allocated = 0;
	
	opts.progname = argv[0];
	opts.image = NULL;
	opts.mountpoint = 0;
	opts.offset = 0;
	if (fuse_opt_parse(&args, &opts, fuse_opts, sqfs_opt_proc) == -1)
		sqfs_usage(argv[0], true);
	if (!opts.image)
		sqfs_usage(argv[0], true);
	
	hl = sqfs_hl_open(opts.image, opts.offset);
	if (!hl)
		return -1;
	
	fuse_opt_add_arg(&args, "-s"); /* single threaded */
	/*ret = fuse_main(args.argc, args.argv, &sqfs_hl_ops, hl);
	fuse_opt_free_args(&args);
	return ret;*/
}
