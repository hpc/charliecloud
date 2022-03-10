# This image tests multi-stage build using GNU Hello. In the first stage, we
# install a build environment and build Hello. In the second stage, we start
# fresh again with a base image and copy the Hello executables. Tests
# demonstrate that Hello runs and none of the build environment is present.
#
# ch-test-scope: standard


FROM almalinux:8 AS buildstage

# Build environment
RUN dnf install -y \
                gcc \
                make \
                wget
WORKDIR /usr/local/src

# GNU Hello. Install using DESTDIR to make copying below easier.
RUN wget -nv https://ftp.gnu.org/gnu/hello/hello-2.10.tar.gz
RUN tar xf hello-2.10.tar.gz \
 && cd hello-2.10 \
 && ./configure \
 && make -j $(getconf _NPROCESSORS_ONLN) \
 && make install DESTDIR=/hello
RUN ls -ld /hello/usr/local/*/*


FROM almalinux:8

RUN dnf install -y man

# COPY the hello install over, by both name and index, making sure not to
# overwrite existing contents. Recall that COPY works different than cp(1).
COPY --from=0 /hello/usr/local/bin /usr/local/bin
COPY --from=buildstage /hello/usr/local/share /usr/local/share
COPY --from=buildstage /hello/usr/local/share/locale /usr/local/share/locale
RUN ls -ld /usr/local/*/*
