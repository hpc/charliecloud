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

void error_int(int retval, char *type, char *spec);
void error_dirp(DIR *ptr, char *type, char *spec);
void error_strud(struct dirent *ptr, char *type, char *spec);
void error_com(int arg, char *type);
void binder(char *ranch, char *corral);
void remount(char *ranch);
void linker(char *ranch, char *corral);

int symlink_ranch(char *im1, char *im2)
{
   //error_com(argc,"Argument Count");
   binder(im1, im2);
   remount(im1);
   linker(im1, im2);
   return 0;
}

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

void binder(char *ranch, char *corral)
{
   error_int(mount(ranch, corral, NULL, MS_BIND, NULL),\
			 "Bind Mount", "Scratch Space");
}

void remount(char *ranch)
{
   error_int(mount("none", ranch, "tmpfs", 0, NULL),\
			   "Mount tmpfs", "Overlay");
}

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

