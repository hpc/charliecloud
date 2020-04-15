examplesdir = $(docdir)/examples

execs = \
chtest/Build \
chtest/bind_priv.py \
chtest/dev_proc_sys.py \
chtest/fs_perms.py \
chtest/printns \
chtest/signal_out.py \
hello/hello.sh

noexecs = \
Dockerfile.alpineedge \
Dockerfile.centos6 \
Dockerfile.centos7 \
Dockerfile.centos8 \
Dockerfile.debian9 \
Dockerfile.exhaustive \
Dockerfile.mpich \
Dockerfile.nvidia \
Dockerfile.openmpi \
Dockerfile.python3 \
Dockerfile.ubuntu1604 \
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
copy/fileA \
copy/fileB \
copy/test.bats \
dont-init-ucx-on-intel-cray.patch \
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
obspy/Dockerfile \
obspy/README \
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
hello/test.bats \
lammps/test.bats \
lustre/test.bats \
mpibench/test.bats \
mpihello/test.bats \
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

all-local:
	ln -fs dirCb copy/dirCa/symlink-to-dirCb
	ln -fs fileDa copy/dirD/symlink-to-fileDa
	ln -fs dirEb copy/dirEa/symlink-to-dirEb
	ln -fs fileA copy/symlink-to-fileA
	ln -fs fileB copy/symlink-to-fileB-A
	ln -fs fileB copy/symlink-to-fileB-B

clean-local:
	rm -f copy/dirCa/symlink-to-dirCb
	rm -f copy/dirD/symlink-to-fileDa
	rm -f copy/dirEa/symlink-to-dirEb
	rm -f copy/symlink-to-fileA
	rm -f copy/symlink-to-fileB-A
	rm -f copy/symlink-to-fileB-B

install-data-hook:
	ln -fs dirCb $(examplesdir)/copy/dirCa/symlink-to-dirCb
	ln -fs fileDa $(examplesdir)/copy/dirD/symlink-to-fileDa
	ln -fs dirEb $(examplesdir)/copy/dirEa/symlink-to-dirEb
	ln -fs fileA $(examplesdir)/copy/symlink-to-fileA
	ln -fs fileB $(examplesdir)/copy/symlink-to-fileB-A
	ln -fs fileB $(examplesdir)/copy/symlink-to-fileB-B

uninstall-local:
	rm -f $(examplesdir)/copy/dirCa/symlink-to-dirCb
	rm -f $(examplesdir)/copy/dirD/symlink-to-fileDa
	rm -f $(examplesdir)/copy/dirEa/symlink-to-dirEb
	rm -f $(examplesdir)/copy/symlink-to-fileA
	rm -f $(examplesdir)/copy/symlink-to-fileB-A
	rm -f $(examplesdir)/copy/symlink-to-fileB-B
