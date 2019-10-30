#export LC_ALL := C 

#images_ch = ch-test/Build \
#			 Build.centos7xz Build.ch-build2dir Build.pull2dir Build.ch-pull2tar Build.missing Build.skopeo-umoci \
#			 Dockerfile.alpine39 Dockerfile.argenv Dockerfile.centos7 Dockerfile.exhaustive Dockerfile.nvidia Dockerfile.python3 \
#		     Dockerfile.alpineedge Dockerfile.centos6 Dockerfile.debian9 Dockerfile.mpich Dockerfile.openmpi Dockerfile.ubuntu1604 \
#			 Docker_Pull.alpine39_dp 
#

#images_ch  = Build.centos7xz Build.ch-build2dir Build.pull2dir Build.ch-pull2tar Build.missing Build.skopeo-umoci \
#			 Dockerfile.alpine39 Dockerfile.argenv Dockerfile.centos7 Dockerfile.exhaustive Dockerfile.nvidia Dockerfile.python3 \
#		     Dockerfile.alpineedge Dockerfile.centos6 Dockerfile.debian9 Dockerfile.mpich Dockerfile.openmpi Dockerfile.ubuntu1604 \
#			 Docker_Pull.alpine39_dp 

images_ch  = Build.centos7xz Build.ch-build2dir Build.ch-pull2tar Build.missing Build.skopeo-umoci \
			 Dockerfile.alpine39 Dockerfile.argenv Dockerfile.centos7 Dockerfile.exhaustive Dockerfile.nvidia Dockerfile.python3 \
		     Dockerfile.alpineedge Dockerfile.centos6 Dockerfile.debian9 Dockerfile.mpich Dockerfile.openmpi Dockerfile.ubuntu1604 \
			 Docker_Pull.alpine39_dp 

images_eg = ../examples/mpi/lammps/Dockerfile ../examples/mpi/mpibench/Dockerfile.mpich ../examples/mpi/mpibench/Dockerfile.openmpi \
			 ../examples/mpi/mpihello/Dockerfile.mpich ../examples/mpi/mpihello/Dockerfile.openmpi ../examples/mpi/paraview/Dockerfile \
			 ../examples/other/spark/Dockerfile ../examples/serial/hello/Dockerfile ../examples/serial/obspy/Dockerfile ../examples/serial/spack/Dockerfile
			 			 
images = $(images_ch) $(images_eg)

#sotests = check-no-icc sotest/bin/sotest sotest/lib/libsotest.so.1.0
sotests = sotest/bin/sotest sotest/lib/libsotest.so.1.0

#bin_PROGRAMS=sotest
#sotest_SOURCES=sotest.c
#sotest_LDADD=libsotest.la
#sotest_LDFLAGS=

#lib_LTLIBRARIES=libsotest.la
#libsotest_la_SOURCES=libsotest.c


# Used by "make all" at top level to build these files for "make install".
.PHONY: all
#all: build_auto.bats run_auto.bats $(sotests)
all: build_auto.bats run_auto.bats $(sotests)


.PHONY: test
test: test-build test-run
#ifneq ($(CH_TEST_SCOPE),quick)
#test: test-test
#endif


.PHONY: test
test: test-build test-run
#if TEST
#	test: test-test
#endif


.PHONY: test-build
test-build: build_auto.bats $(sotests)
	bats build.bats build_auto.bats build_post.bats

# Note: This will will not find ch-run correctly if $CWD is not the test
# directory, which I believe is assumed elsewhere in the test suite as well.
.PHONY: test-run
test-run: run_auto.bats $(sotests)
	bats run_first.bats run_auto.bats run/*.bats
	set -e; \
	if [ "$$CH_TEST_SCOPE" != "quick" ]; then \
	    for GUEST_USER in $$(id -un) root nobody; do \
	        for GUEST_GROUP in $$(id -gn) root $$(id -gn nobody); do \
	            export GUEST_USER; \
	            export GUEST_GROUP; \
	            echo testing as: $$GUEST_USER $$GUEST_GROUP; \
	            bats run/ch-run_uidgid.bats; \
	        done; \
	    done; \
	fi

# FIXME: This could be sped up by skipping bats if the image is out of scope.


.PHONY: test-test
test-test: $(images_eg)
	set -e; \
	for image in $(images_eg); do \
	    export CH_TEST_TAG=$$(./make-auto tag $$image); \
	    bats $$(dirname $$image)/test.bats; \
	done

#.PHONY: clean
clean-local:
	rm -f *_auto.bats
	rm -f sotest/sotest sotest/libsotest.so*
	rm -f sotest/bin/sotest sotest/lib/libsotest.so*

.PHONY: where-bats
where-bats:
	which bats
	bats --version

build_auto.bats: $(images) make-auto
	./make-auto build $^ > $@

run_auto.bats: $(images) make-auto
	./make-auto run $^ > $@

sotest/bin/sotest: sotest/sotest
	cp -a $^ $@
sotest/lib/libsotest.so.1.0: sotest/libsotest.so.1.0
	cp -a $^ $@


#check-no-icc:
#ifeq ($(patsubst %icc,,$(lastword $(CC))),)
#    $(error ICC not supported since it overlinks extra shared libraries)
#endif

sotest/sotest: sotest/sotest.c sotest/libsotest.so.1.0
	$(CC) -o $@ $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -L./sotest -lsotest $^

sotest/libsotest.so.1.0: sotest/libsotest.c
	$(CC) -o $@ $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -shared -fPIC -Wl,-soname,libsotest.so.1 -lc $^
	ln -f -s libsotest.so.1.0 sotest/libsotest.so
	ln -f -s libsotest.so.1.0 sotest/libsotest.so.1
