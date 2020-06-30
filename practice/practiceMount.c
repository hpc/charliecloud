#include <stdio.h>
#include <fuse.h>
static int read_callback(const char *path, char *buf, size_t size, off_t offset, struct fuse_file_info *fi);

//include <fuse_opt.h>  //for fuse_args struct
int main (int argc, char* argv)
{
	 

	//ch-mount <filename> <parent dir>
	
	//int fuse_mount(struct fuse *f, const char *mountpoint);
	

	struct fuse_args args = FUSE_ARGS_INIT(argc,argv);
	struct fuse_operations *ops;
		*ops.read = read_callback;
	size_t op_size = 0; //something like this but more correct
	void* user_data; 
	struct fuse *f;
	//struct &f fuse_new(args, ops, op_size, private_data);
	//fuse_mount(&fuse, "parentdir");

	fuse_main_real(argc, argv, *ops, op_size, *user_data);
}	

static int read_callback(const char *path, char *buf, size_t size, off_t offset, struct fuse_file_info *fi) 
{
	 int retstat = 0;
    
    log_msg("bb_read(path=\"%s\", buf=0x%08x, size=%d, offset=%lld, fi=0x%08x)\n",
	    path,  (int) buf, size,  offset,  (int) fi);
    
    retstat = pread(fi->fh, buf, size, offset);
    if (retstat < 0)
	retstat = bb_error("bb_read read");
    
    return retstat;

}						
