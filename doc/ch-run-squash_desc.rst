Description
===============================================================
By default, :code:`ch-run` expects that the squash filesystem is already
mounted. Using :code:`--squash` it mounts and un-mount the :code:`SQFS`.

The :code:`SQFS` mounts, run and unmounts by:

1. :code:`ch-run` parses the arguments from the user and sends into :code:`squashmount()`
   within :code:`ch_core.c` It creates a sub-directory in the default :code:`/var/tmp`
   or the user input of :code:`DIR`.

2. We get the fuse operations from :code:`get_fuse_ops()` in our new squashfuse API, :code:`ops.c`, 
   along with updating and initalizing other arguments that are needed.
 
3. The :code:`SQFS` gets mounted in mountpoint sub-directory determined previously.

4. Signal handlers are initalized in order to run the code and fork a new process
   so :code:`fuse_loop()` can continue running.

5. The :code:`ch-run` workflow continues as usual. The third process is forked to run the desired code
   using :code:`execvp()`.The parent process waits until :code:`ch-run` is completed.

6. Lastly the environment gets cleaned up. The signal handlers are removed, the :code:`SQFS`
   gets unmounted and the sub-directory is removed. 

Multiple processes in the same container with :code:`--squash`
================================================================
Three proccess are needed in the same container to perform such tasks:

* :code:`fuse_loop()`: continues to run until the process is killed.
  This is needed to :code:`ch-run`
* waiting for :code:`execvp()` to run: this process waits for
  :code:`ch-run` to finish running inorder to know when to un-mount
* :code:`execvp()`: runs as :code:`ch-run`
