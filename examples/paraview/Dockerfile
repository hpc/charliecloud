# ch-test-scope: full
# ch-test-builder-exclude: ch-grow  # deferred
FROM openmpi
WORKDIR /usr/local/src

RUN dnf install -y \
    cmake \
    expat-devel \
    libpng-devel \
    llvm \
    llvm-devel \
    python3 \
    python3-devel \
    python3-mako \
    python3-pip

RUN pip3 install --no-binary=mpi4py \
    cython \
    mpi4py


# Mesa. We need a version newer than Debian provides. Not sure which bug fix
# resolved it but versions prior to 19 appear to have issues rendering on ARM.
ENV MESA_VERSION 19.0.5
RUN wget -nv https://mesa.freedesktop.org/archive/mesa-${MESA_VERSION}.tar.xz
RUN tar xf mesa-${MESA_VERSION}.tar.xz
RUN    cd mesa-${MESA_VERSION} \
    && ./configure --prefix=/usr \
                   --enable-autotools \
                   --enable-opengl \
                   --disable-gles1 \
                   --disable-gles2 \
                   --disable-va \
                   --disable-xvmc \
                   --disable-vdpau \
                   --disable-dri \
                   --disable-egl \
                   --disable-gbm \
                   --disable-glx \
                   --disable-osmesa \
                   --enable-shared-glapi \
                   --enable-llvm \
                   --enable-llvm-shared-libs \
                   --enable-gallium-osmesa \
                   --with-gallium-drivers=swrast \
                   --with-dri-drivers= \
                   --with-platforms= \
    && make -j$(getconf _NPROCESSORS_ONLN) install
RUN rm -Rf mesa-${MESA_VERSION}*
# ParaView. Use system libpng to work around issues linking with NEON specific
# symbols on ARM.
ENV PARAVIEW_MAJORMINOR 5.6
ENV PARAVIEW_VERSION 5.6.2
RUN wget -nv -O ParaView-v${PARAVIEW_VERSION}.tar.xz "https://www.paraview.org/paraview-downloads/download.php?submit=Download&version=v${PARAVIEW_MAJORMINOR}&type=binary&os=Sources&downloadFile=ParaView-v${PARAVIEW_VERSION}.tar.xz"
RUN tar xf ParaView-v${PARAVIEW_VERSION}.tar.xz
RUN mkdir ParaView-v${PARAVIEW_VERSION}.build
RUN    cd ParaView-v${PARAVIEW_VERSION}.build \
    && cmake -DCMAKE_INSTALL_PREFIX=/usr \
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
    && make -j $(getconf _NPROCESSORS_ONLN) install
RUN rm -Rf ParaView-v${PARAVIEW_VERSION}*
