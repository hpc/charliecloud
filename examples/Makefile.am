examplesdir = $(docdir)/examples

execs = \
chtest/Build \
chtest/bind_priv.py \
chtest/dev_proc_sys.py \
chtest/fs_perms.py \
chtest/printns \
chtest/signal_out.py \
distroless/hello.py \
hello/hello.sh \
obspy/hello.py

noexecs = \
Dockerfile.centos_7ch \
Dockerfile.almalinux_8ch \
Dockerfile.debian_9ch \
Dockerfile.libfabric \
Dockerfile.mpich \
Dockerfile.nvidia \
Dockerfile.openmpi \
chtest/Makefile \
chtest/chroot-escape.c \
chtest/mknods.c \
chtest/setgroups.c \
chtest/setuid.c \
copy/Dockerfile \
copy/dirA/fileAa \
copy/dirB/fileBa \
copy/dirB/fileBb \
copy/dirCa/dirCb/fileCba \
copy/dirCa/dirCb/fileCbb \
copy/dirD/fileDa \
copy/dirEa/dirEb/fileEba \
copy/dirEa/dirEb/fileEbb \
copy/dirF/dir19a3/file19b1 \
copy/dirF/file19a3 \
copy/dirF/file19a2 \
copy/dirF/dir19a2/file19b2 \
copy/dirF/dir19a2/dir19b2/file19c1 \
copy/dirF/dir19a2/dir19b3/file19c1 \
copy/dirF/dir19a2/file19b3 \
copy/dirG/diry/file_ \
copy/dirG/filey \
copy/dirG/s_dir1 \
copy/dirG/s_dir4/file_ \
copy/dirG/s_file1 \
copy/dirG/s_file4/file_ \
copy/fileA \
copy/fileB \
copy/test.bats \
distroless/Dockerfile \
exhaustive/Dockerfile \
hello/Dockerfile \
hello/README \
lammps/Dockerfile \
lammps/melt.patch \
lammps/simple.patch \
lustre/Dockerfile \
mpibench/Dockerfile.mpich \
mpibench/Dockerfile.openmpi \
mpihello/Dockerfile.mpich \
mpihello/Dockerfile.openmpi \
mpihello/Makefile \
mpihello/hello.c \
mpihello/slurm.sh \
multistage/Dockerfile \
obspy/Dockerfile \
obspy/README \
obspy/obspy.png \
paraview/Dockerfile \
paraview/cone.2ranks.vtk \
paraview/cone.nranks.vtk \
paraview/cone.png \
paraview/cone.py \
paraview/cone.serial.vtk \
spack/Dockerfile \
spark/Dockerfile \
spark/slurm.sh

batsfiles = \
distroless/test.bats \
exhaustive/test.bats \
hello/test.bats \
lammps/test.bats \
lustre/test.bats \
mpibench/test.bats \
mpihello/test.bats \
multistage/test.bats \
obspy/test.bats \
paraview/test.bats \
spack/test.bats \
spark/test.bats

nobase_examples_SCRIPTS = $(execs)

nobase_examples_DATA = $(noexecs)
if ENABLE_TEST
nobase_examples_DATA += $(batsfiles)
endif

EXTRA_DIST = $(execs) $(noexecs) $(batsfiles)

# Automake is completely unable to deal with symlinks; we cannot include them
# in the source code or "make dist" won't work, and we can't include them in
# the files to install or "make install" won't work. These targets take care
# of everything manually.
#
# Note: -T prevents ln(1) from dereferencing and descending into symlinks to
# directories. Without this, new symlinks are created within such directories,
# instead of replacing the existing symlink as we wanted. See PR #722.

all-local:
	ln -fTs dirCb copy/dirCa/symlink-to-dirCb
	ln -fTs fileDa copy/dirD/symlink-to-fileDa
	ln -fTs dirEb copy/dirEa/symlink-to-dirEb
	ln -fTs filey copy/dirG/s_dir2
	ln -fTs diry copy/dirG/s_dir3
	ln -fTs filey copy/dirG/s_file2
	ln -fTs diry copy/dirG/s_file3
	ln -fTs fileA copy/symlink-to-fileA
	ln -fTs fileB copy/symlink-to-fileB-A
	ln -fTs fileB copy/symlink-to-fileB-B

clean-local:
	rm -f copy/dirCa/symlink-to-dirCb
	rm -f copy/dirD/symlink-to-fileDa
	rm -f copy/dirEa/symlink-to-dirEb
	rm -f copy/dirG/s_dir2
	rm -f copy/dirG/s_dir3
	rm -f copy/dirG/s_file2
	rm -f copy/dirG/s_file3
	rm -f copy/symlink-to-fileA
	rm -f copy/symlink-to-fileB-A
	rm -f copy/symlink-to-fileB-B

install-data-hook:
	ln -fTs dirCb $(DESTDIR)$(examplesdir)/copy/dirCa/symlink-to-dirCb
	ln -fTs fileDa $(DESTDIR)$(examplesdir)/copy/dirD/symlink-to-fileDa
	ln -fTs dirEb $(DESTDIR)$(examplesdir)/copy/dirEa/symlink-to-dirEb
	ln -fTs filey $(DESTDIR)$(examplesdir)/copy/dirG/s_dir2
	ln -fTs diry $(DESTDIR)$(examplesdir)/copy/dirG/s_dir3
	ln -fTs filey $(DESTDIR)$(examplesdir)/copy/dirG/s_file2
	ln -fTs diry $(DESTDIR)$(examplesdir)/copy/dirG/s_file3
	ln -fTs fileA $(DESTDIR)$(examplesdir)/copy/symlink-to-fileA
	ln -fTs fileB $(DESTDIR)$(examplesdir)/copy/symlink-to-fileB-A
	ln -fTs fileB $(DESTDIR)$(examplesdir)/copy/symlink-to-fileB-B

uninstall-local:
	rm -f $(DESTDIR)$(examplesdir)/copy/dirCa/symlink-to-dirCb
	rm -f $(DESTDIR)$(examplesdir)/copy/dirD/symlink-to-fileDa
	rm -f $(DESTDIR)$(examplesdir)/copy/dirEa/symlink-to-dirEb
	rm -f $(DESTDIR)$(examplesdir)/copy/dirG/s_dir2
	rm -f $(DESTDIR)$(examplesdir)/copy/dirG/s_dir3
	rm -f $(DESTDIR)$(examplesdir)/copy/dirG/s_file2
	rm -f $(DESTDIR)$(examplesdir)/copy/dirG/s_file3
	rm -f $(DESTDIR)$(examplesdir)/copy/symlink-to-fileA
	rm -f $(DESTDIR)$(examplesdir)/copy/symlink-to-fileB-A
	rm -f $(DESTDIR)$(examplesdir)/copy/symlink-to-fileB-B

uninstall-hook:
	rmdir $$(find $(docdir) -type d | sort -r)

