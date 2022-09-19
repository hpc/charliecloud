# ch-test-scope: full
FROM openmpi
WORKDIR /usr/local/src

RUN dnf install -y --setopt=install_weak_deps=false \
                cmake \
                expat-devel \
                libpng-devel \
                llvm \
                llvm-devel \
                mesa-libGL \
                mesa-libGL-devel \
                mesa-libOSMesa \
                mesa-libOSMesa-devel \
                python3 \
                python3-devel \
                python3-mako \
                python3-pip \
                which \
                zlib-devel \
 && dnf clean all

RUN pip3 install --no-binary=mpi4py \
    cython \
    mpi4py

WORKDIR /usr/local/src

# Install ImageMagick
# The latest, 7.1.0, fails to install with a cryptic libtool error. ¯\_(ツ)_/¯
ARG MAGICK_VERSION=7.0.11-14
RUN wget -nv -O ImageMagick-${MAGICK_VERSION}.tar.gz \
    "https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${MAGICK_VERSION}.tar.gz" \
 && tar xf ImageMagick-${MAGICK_VERSION}.tar.gz \
 && cd ImageMagick-${MAGICK_VERSION} \
 && ./configure --prefix=/usr/local \
 && make -j $(getconf _NPROCESSORS_ONLN) install \
 && rm -Rf ../ImageMagick-${MAGICK_VERSION}

# ParaView. Use system libpng to work around issues linking with NEON specific
# symbols on ARM.
ARG PARAVIEW_MAJORMINOR=5.9
ARG PARAVIEW_VERSION=5.9.1
RUN wget -nv -O ParaView-v${PARAVIEW_VERSION}.tar.xz "https://www.paraview.org/paraview-downloads/download.php?submit=Download&version=v${PARAVIEW_MAJORMINOR}&type=binary&os=Sources&downloadFile=ParaView-v${PARAVIEW_VERSION}.tar.xz" \
 && tar xf ParaView-v${PARAVIEW_VERSION}.tar.xz \
 && mkdir ParaView-v${PARAVIEW_VERSION}.build \
 && cd ParaView-v${PARAVIEW_VERSION}.build \
 && cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
          -DCMAKE_BUILD_TYPE=Release \
          -DBUILD_TESTING=OFF \
          -DBUILD_SHARED_LIBS=ON \
          -DPARAVIEW_ENABLE_PYTHON=ON \
          -DPARAVIEW_BUILD_QT_GUI=OFF \
          -DVTK_USE_X=OFF \
          -DOPENGL_INCLUDE_DIR=IGNORE \
          -DOPENGL_gl_LIBRARY=IGNORE \
          -DVTK_OPENGL_HAS_OSMESA=ON \
          -DVTK_USE_OFFSCREEN=OFF \
          -DPARAVIEW_USE_MPI=ON \
          -DPYTHON_EXECUTABLE=/usr/bin/python3 \
          -DVTK_USE_SYSTEM_PNG=ON \
    ../ParaView-v${PARAVIEW_VERSION} \
 && make -j $(getconf _NPROCESSORS_ONLN) install \
 && rm -Rf ../ParaView-v${PARAVIEW_VERSION}*

# Add bind-mount DST files and directories for example tests.
RUN mkdir /diff \
 && echo "example bind mount DST file" > /inp_a \
 && echo "example bind mount DST file" > /inp_b
