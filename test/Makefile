export LC_ALL := C
sotests := check-no-icc sotest/bin/sotest sotest/lib/libsotest.so.1.0

# Used by "make all" at top level to build shared objects for testing.
.PHONY: all
all: $(sotests)

sotest/bin/sotest: sotest/sotest
	cp -a $^ $@
sotest/lib/libsotest.so.1.0: sotest/libsotest.so.1.0
	cp -a $^ $@

.PHONY: clean
clean:
	rm -f sotest/sotest sotest/libsotest.so*
	rm -f sotest/bin/sotest sotest/lib/libsotest.so*
	rm bin
# We exclude icc here because it links the
# resulting binaries with extra shared libraries that are then not copied into
# the container. (Issue #227.)
check-no-icc:
ifeq ($(patsubst %icc,,$(lastword $(CC))),)
	$(error ICC not supported since it overlinks extra shared libraries)
endif

sotest/sotest: sotest/sotest.c sotest/libsotest.so.1.0
	$(CC) -o $@ $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -L./sotest -lsotest $^
sotest/libsotest.so.1.0: sotest/libsotest.c
	$(CC) -o $@ $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -shared -fPIC -Wl,-soname,libsotest.so.1 -lc $^
	ln -f -s libsotest.so.1.0 sotest/libsotest.so
	ln -f -s libsotest.so.1.0 sotest/libsotest.so.1

.PHONY: install
install: all
	cd ../ && \
	for i in examples/serial/* examples/mpi/* examples/other/*; do \
		install -d $(LIBEXEC_INST)/$$i; \
		install -pm 644 -t $(LIBEXEC_INST)/$$i $$i/*; \
	done
	chmod 755 $(LIBEXEC_INST)/examples/serial/hello/hello.sh \
	          $(LIBEXEC_INST)/examples/*/*/*.sh
	find $(LIBEXEC_INST)/examples -name Build -exec chmod 755 {} \;
#	tests
	install -d $(TEST) $(TEST)/run
	install -pm 644 -t $(TEST) *.bats common.bash Makefile
	install -pm 644 -t $(TEST)/run run/*.bats
	install -pm 755 -t $(TEST) Build.*
	install -pm 644 -t $(TEST) Dockerfile.* Docker_Pull.*
	install -pm 644 -t $(TEST) *.patch
	install -pm 755 -t $(TEST) chtest-make-auto \
							   docs-sane \
                               make-perms-test
	install -d $(TEST)/chtest
	install -d $(TEST)/make-auto.d
	install -pm 644 -t $(TEST)/make-auto.d make-auto.d/*
	install -pm 644 -t $(TEST)/chtest chtest/*
	chmod 755 $(TEST)/chtest/Build \
	          $(TEST)/chtest/*.py \
	          $(TEST)/chtest/printns
#	shared library tests
	install -d $(TEST)/sotest $(TEST)/sotest/bin $(TEST)/sotest/lib
	install -pm 755 -t $(TEST)/sotest sotest/libsotest.so.1.0 \
	                                  sotest/sotest
	install -pm 644 -t $(TEST)/sotest sotest/files_inferrable.txt \
	                                  sotest/libsotest.c \
	                                  sotest/sotest.c
	ln -sf ./libsotest.so.1.0 $(TEST)/sotest/libsotest.so
	ln -sf ./libsotest.so.1.0 $(TEST)/sotest/libsotest.so.1
	install -pm 755 -t $(TEST)/sotest/bin sotest/bin/sotest
	install -pm 755 -t $(TEST)/sotest/lib sotest/lib/libsotest.so.1.0
