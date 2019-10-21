export LC_ALL := C

images_ch = ch-test/Build \
			 Build.centos7xz Build.ch-build2dir Build.pull2dir Build.ch-pull2tar Build.missing Build.skopeo-umoci \
			 Dockerfile.alpine39 Dockerfile.argenv Dockerfile.centos7 Dockerfile.exhaustive Dockerfile.nvidia Dockerfile.python3 \
		     Dockerfile.alpineedge Dockerfile.centos6 Dockerfile.debian9 Dockerfile.mpich Dockerfile.openmpi Dockerfile.ubuntu1604 \
			 Docker_Pull.alpine39_dp 

images_eg = ../examples/mpi/lammps/Dockerfile ../examples/mpi/mpibench/Dockerfile.mpich ../examples/mpi/mpibench/Dockerfile.openmpi \
			 ../examples/mpi/mpihello/Dockerfile.mpich ../examples/mpi/mpihello/Dockerfile.openmpi ../examples/mpi/paraview/Dockerfile \
			 ../examples/other/spark/Dockerfile ../examples/serial/hello/Dockerfile ../examples/serial/obspy/Dockerfile ../examples/serial/spack/Dockerfile
			 			 
images = $(images_ch) $(images_eg)

bin_PROGRAMS=sotest
sotest_SOURCES=sotest.c
sotest_LDADD=libsotest.la
sotest_LDFLAGS=

lib_LTLIBRARIES=libsotest.la
libsotest_la_SOURCES=libsotest.c
