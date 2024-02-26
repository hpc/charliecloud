# ch-test-scope: skip  #1810
FROM openmpi
WORKDIR /usr/local/src

# The mesa rpms introduce explicit dependencies python3.11-libs; ParaView will
# error at configure time unless we provide the python3.11-devel package.
RUN dnf install -y --setopt=install_weak_deps=false \
                cmake \
                expat-devel \
                llvm \
                llvm-devel \
                mesa-libGL \
                mesa-libGL-devel \
                mesa-libOSMesa \
                mesa-libOSMesa-devel \
                python3-mako \
                python3-pip \
                python3.11-devel \
                zlib-devel \
 && dnf clean all

RUN pip3 install --no-binary=mpi4py \
    cython \
    mpi4py

WORKDIR /usr/local/src

# ParaView. Use system libpng to work around issues linking with NEON specific
# symbols on ARM.
ARG PARAVIEW_MAJORMINOR=5.11
ARG PARAVIEW_VERSION=5.11.2
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
