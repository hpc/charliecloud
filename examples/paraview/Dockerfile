# ch-test-scope: full
# ch-test-builder-exclude: ch-grow  # deferred
FROM openmpi
WORKDIR /usr/src

RUN apt-get install -y \
    python-dev \
    python-pip
RUN pip install \
    cython \
    mpi4py
RUN apt-get install -y \
    cmake \
    git \
    python-mako \
    libpng-dev \
    libpthread-stubs0-dev \
    libqt4-dev \
    libxt-dev \
    pkg-config \
    qt4-qmake \
    zlib1g-dev

# LLVM. Using version 7 to resolve segfaults seen with version 3.
ENV LLVM_VERSION 7.0.1
RUN wget -nv http://releases.llvm.org/${LLVM_VERSION}/llvm-${LLVM_VERSION}.src.tar.xz
RUN tar xf llvm-${LLVM_VERSION}.src.tar.xz
RUN mkdir llvm-${LLVM_VERSION}.build
RUN    cd llvm-${LLVM_VERSION}.build \
    && cmake -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_INSTALL_PREFIX=/usr \
             -DLLVM_BUILD_LLVM_DYLIB=ON \
             -DLLVM_LINK_LLVM_DYLIB=ON \
             -DLLVM_ENABLE_RTTI=ON \
             -DLLVM_INSTALL_UTILS=ON \
             -DLLVM_TARGETS_TO_BUILD="AArch64;X86" \
             ../llvm-${LLVM_VERSION}.src \
    && make -j $(getconf _NPROCESSORS_ONLN) install
RUN rm -Rf llvm-${LLVM_VERSION}*

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
ENV PARAVIEW_MAJORMINOR 5.5
ENV PARAVIEW_VERSION 5.5.2
RUN wget -nv -O ParaView-v${PARAVIEW_VERSION}.tar.gz "https://www.paraview.org/paraview-downloads/download.php?submit=Download&version=v${PARAVIEW_MAJORMINOR}&type=binary&os=Sources&downloadFile=ParaView-v${PARAVIEW_VERSION}.tar.gz"
RUN tar xf ParaView-v${PARAVIEW_VERSION}.tar.gz
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
             -DVTK_USE_SYSTEM_PNG=ON \  
        ../ParaView-v${PARAVIEW_VERSION} \
    && make -j $(getconf _NPROCESSORS_ONLN) install
RUN rm -Rf ParaView-v${PARAVIEW_VERSION}*
