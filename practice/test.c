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
	struct fuse_args args = FUSE_ARGS_INIT(0, NULL);
	args.allocated = 1;
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
	
	//set up the mount
	fuse_opt_add_arg(&args, argv[0]);
	ch = fuse_mount(mountdir,&args);
	if(!ch){
		fuse_opt_free_args(&args);
		return 1;
	}
	
	//set up the fuse session
	fuse = fuse_new(ch,&args, &sqfs_hl_ops, sizeof(sqfs_hl_ops), hl);
	if(fuse == NULL){
		printf("bois");
	}

	//set up signal handlers
	if(0 > fuse_set_signal_handlers(fuse_get_session(fuse))){
		printf("bois2");
	}

	//run the session handler in the child process, and carry  on in the parent
	if(fork() == 0){
		ret = fuse_loop(fuse);
		fuse_teardown(fuse, mountdir);
	} else {
		fuse_exit(fuse);
		return ret;
	}
	return ret; 
}


	
