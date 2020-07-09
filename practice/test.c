#include <ops.h>
#include <libgen.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <fuse.h>
//#include <fuse_lowlevel.h>
int main(int argc, char *argv[]) {
	//fuse args struct
	struct fuse_args args;
	//sqfs struct
	sqfs_hl *hl;
	//return value
	int ret;
	//struct fuse
	struct fuse *fuse;
        // the chan
        struct fuse_chan *ch;
        //get fuse operations struct from external libraries
	fuse_operations sqfs_hl_ops;
        get_fuse_ops(&sqfs_hl_ops);
	
	//create sqfs struct with path to image, and offset
	hl =sqfs_hl_open(argv[1], 0);
	if (!hl)
		return -1;

	//make the directory to mount
	char *name = strtok(basename(argv[1]),".");
	char * buffer = (char *) malloc(strlen(name) + 10);
	strcpy(buffer, "/var/tmp/");
	char *mountdir = strcat(buffer, name);	
	if(mkdir(mountdir, 0777) != 0){
		return -1;
	}
	char *mountpoint;
	fuse_opt_add_arg(&args, argv[0]);
        //fuse_opt_add_arg(&args, mountdir);
        //fuse_opt_add_arg(&args, "-f");   
	ch = fuse_mount(mountdir,&args);
	if(!ch){
		fuse_opt_free_args(&args);
		return 1;
	}
	fuse = fuse_new(ch,&args, &sqfs_hl_ops, sizeof(sqfs_hl_ops), hl);
	//fuse = fuse_setup(args.argc, args.argv, &sqfs_hl_ops, sizeof(sqfs_hl_ops), &mountpoint, 0, hl);
	
	if(fuse == NULL){
		printf("bois");
	}
	//if(0 > fuse_daemonize(0)){
	//	printf("bois3");
	//}
	if(0 > fuse_set_signal_handlers(fuse_get_session(fuse))){
		printf("bois2");
	}
	ret = fuse_loop(fuse);
	fuse_teardown(fuse, mountpoint);
	return ret;
	//pass in arguments to fuse main containing program name, mount location, single threaded option
	/**
	struct fuse_chan *ch;
	ifuse_opt_add_arg(&args, argv[0]);
	//fuse_opt_add_arg(&args, mountdir); 	
	fuse_opt_add_arg(&args, "-s");
		
	ch = fuse_mount(mountdir, &args);
	if(!ch){
		printf("bruh");
		return -1;
	}
	fuse = fuse_new(ch,&args, &sqfs_hl_ops,sizeof(sqfs_hl_ops), NULL);
	//fuse_opt_free_args(&args);i
	*/
	return ret; 
}



