/*This is a work in progress process for its implementation into\
 Charliecloud.
*/
#define  _GNU_SOURCE
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/types.h>
#include <dirent.h>

#include "charliecloud.h"

//Prototypes
void error_int(int retval, char *type, char *spec);
void error_dirp(DIR *ptr, char *type, char *spec);
void error_strud(struct dirent *ptr, char *type, char *spec);
void error_com(int arg, char *type);
void binder(char *ranch, char *corral);
void remount(char *ranch);
void linker(char *ranch, char *corral);

/*The symlink-ranch() encapsulates the following functions below to\
trick the system into making the read-only image writable.
*/
void symlink_ranch(char *im1, char *im2)
{
   //error_com(argc,"Argument Count");
   binder(im1, im2);
   remount(im1);
   linker(im1, im2);
}

/*The following functions checks the condition of the read-only image\
These additions work to make the symlink-ranch reliable. 
*/

/*error_com() is an error checking for the correct amount of arguments\
on the comand line
*/
void error_com(int arg, char *type)
{
   if(arg == 3)
      printf("%s : %d : Success\n", type, arg);
   else
   {
      printf("%s : %d : 3 arguments available: exited\n", type, arg);
      exit(0);
   }
}

/*error_int() checks the processes with return values of integers to see if\
errno has stopped the process.
*/
void error_int(int retval, char *type, char *spec)
{
   if(retval == 0)
      printf("%s : %s created : Success\n", type, spec);
   else
   {
      printf("%s : %s was not created : Errno is %d: %s\n",\
		      type, spec, retval, strerror(retval));
      exit(0);
   }	
}

//error_ptr() does the same as above for those that return a ptr.
void error_ptr(void *ptr, char *type, char *spec)
{
   if(ptr)
      printf("%s : %s : Success\n", type, spec);
   else	
   {
      printf("%s : %s errno %d : %s\n",type,\
	       spec, errno, strerror(errno));
      exit(0);
   }
}

/*binder() bind mount the read-only image ranch to the scratch space image\
which in this case is corral.\
This preserves our data from the read-only image to a seperate space.
*/
void binder(char *ranch, char *corral)
{
   error_int(mount(ranch, corral, NULL, MS_BIND, NULL),\
			 "Bind Mount", "Scratch Space");
}

/*remount() mounts a tmpfs to the read-only image ranch\
This serves the purpose to overlay a file system in order to\
obtain the write permission.
*/
void remount(char *ranch)
{
   error_int(mount("none", ranch, "tmpfs", 0, NULL),\
			   "Mount tmpfs", "Overlay");
}

/*linker() is where the magic happens. With the combination of\
reddir() and opendir() we are able to take the scratch space image (corral)\
and read in each of those files found and symlink each of those files found\
to the read-only image (ranch). This restores your original data while\
also alowing for flexibility with a read-write image.
*/
void linker(char *ranch, char *corral)
{
   DIR *d_ptr = opendir(corral);
   struct dirent *struck;
   char *nam, *src, *dest;

   error_ptr(d_ptr,"Open Directory", "Scratch Space");

   while(true)
   {
      struck = readdir(d_ptr);	   
      nam = struck->d_name;

      error_ptr(struck,"Read Directory","DIR ptr");

      if(struck == NULL)
         break;
      if(strcmp(nam,".") == 0 || strcmp(nam,"..") == 0)
      {	
         printf("%s\n", nam);
         continue;
      }

      printf("%s\n",nam);
      asprintf(&src, "%s/%s", corral, nam);
      asprintf(&dest, "%s/%s", ranch, nam);
      printf("%s\n%s\n",src,dest);

      error_int(symlink(src,dest), "Symlink", nam);

      free(src);
      free(dest);
														     }
}

