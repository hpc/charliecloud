#include <ops.h>

int main(int argc, char *argv[]) {
	//fuse args struct
	struct fuse_args args;
	//sqfs struct
	sqfs_hl *hl;
	//return value
	int ret;
        
        //get fuse operations struct from external libraries
	struct fuse_operations sqfs_hl_ops;
        get_fuse_ops(&sqfs_hl_ops);
	
	//create sqfs struct with path to image, and offset	
	hl =sqfs_hl_open(argv[1], 0);
	if (!hl)
		return -1;

	//pass in arguments to fuse main containing program name, mount location, single threaded option
	fuse_opt_add_arg(&args, argv[0]);
	fuse_opt_add_arg(&args, "/var/tmp/anna"); 	
	fuse_opt_add_arg(&args, "-s"); /* single threaded */
	ret = fuse_main(args.argc, args.argv, &sqfs_hl_ops, hl);
	fuse_opt_free_args(&args);
	return ret;
}



