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
Dockerfile.alpine39 \
Dockerfile.alpineedge \
Dockerfile.centos6 \
Dockerfile.centos7 \
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
dont-init-ucx-on-intel-cray.patch \
hello/Dockerfile \
hello/README \
lammps/Dockerfile \
lammps/melt.patch \
lammps/simple.patch \
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
