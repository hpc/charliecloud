Description
===============================================================
It auto-mounts, run and unmount by:

1. :code:`ch-run` parses the arguments from users and send into :code:`squashmount()`
   inside :code:`ch_core`. It creates a sub-directory in the default :code:`/var/tmp`
   or :code:`DIR`.

2. We get the fuse operations from :code:`get_fuse_ops()` along with updating and
   initalizing the arguments.
 
3. The :code:`SQFS` gets mounted in mountpoint determined above.

4. Signal handlers are initalized inorder to run the code and open a new process
   so :code:`fuse_loop` can run.

5. :code:`ch-run` continues to run. The next process is created to run :code:`execvp()`.
   That process waits until :code:`execvp()` is done running.

6. The last process is killed and the squash filesystem is unmounted and the sub-directory
   is removed. All the processes are killed.

Multiple processes in the same container with :code:`--squash`
================================================================
By default, :code:`ch-run` espects that the squash filesystem is already
mounted. Using :code:`--squash` it auto-mounts and un-mount the squash
file system.

Three proccess are needed in the same container to perform such tasks:

* :code:`fuse_loop()`: continues to run until the process is killed.
  This is needed to :code:`ch-run`
* waiting for :code:`execvp()` to run: this process waits for
  :code:`ch-run` to finish running inorder to know when to un-mount
* :code:`execvp()`: runs as :code:`ch-run`
