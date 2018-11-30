# ch-test-scope: full
FROM nvcr.io/hpc/candle:20180326

# The primary goals of this Dockerfile are:
#   
#    1. Provide users with a CANDLE image that builds from start to finish 
#       without user intervention.
#
#    2. Supply data before runtime. Enable the container to run the Pilot1 
#       P1B1 and Pilot3 P3B1 benchmarks on systems without network access 
#       at run time.
#       
# This Dockerfile is an extenstion of NVIDIA's CANDLE Dockerfile, which 
# can be found on their GPU catalog at:
#   
#   - https://ngc.nvidia.com/catalog/containers/hpc%2Fcandle
#
# This Dockerfile requires an authenticated docker login to nvcr.io. To do
# this you must:
#
#   1. Create an account at https://ngc.nvidia.com/catalog/containers
#   2. Click on "CONFIGURATION" located on primary naviation bar on the 
#      left side of the website
#   3. Click the "Get API Key" button
#   4. Record the generated password (key)
#   5. On the command line, login as follows:
#       
#       $ docker login nvcr.io
#       
#       Username: $oauthtoken       # Type this exactly. 
#       Passowrd                    # Enter your your generated key
#
# This Dockerfile is a work in progress. We are always interested in 
# feedback.
#
# The NVIDIA CANDLE Dockerfile does not build completely. Rather they 
# instruct the user to launch an interactive container and resume building.
# From their image documentation:
# 
#    To complete CANDLE setup, execute source /opt/candle_setup.sh Next, 
#    copy the script located in ‘/opt/testscript.sh’ to some other directory
#    inside the container and execute it. This script clones the CANDLE 
#    Benchmark and Tutorials suites and downloads the appropriate data to 
#    run a CANDLE hyperparameter optimization sweep. 
#
# We prefer to encapsulate the entire build process within the Dockerfile. 
# Therefore the remainder of this Dockerfile installs and configures the 
# various dependancies required to run CANDLE (the steps that the user was 
# expected to complete during runtime).

# FIX: Remove.
COPY docker-env.sh /

COPY requirements.txt /opt

WORKDIR /opt
RUN pip install --upgrade pip && \
    pip install -r requirements.txt

ENV PATH="/usr/bin:${PATH}"
ENV BUILD_DIR /opt

RUN rm -rf swift-t 2> /dev/null

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    default-jdk \
    git \
    ant \
    swig \
    zsh \
    tcl \
    tcl-dev \
    python-tk

RUN rm -rf /var/lib/apt/lists/* && \
    wget http://swift-lang.github.io/swift-t-downloads/1.4/swift-t-1.4.tar.gz && \
    tar -zxvf swift-t-1.4.tar.gz && \
    $BUILD_DIR/swift-t-1.4/dev/build/init-settings.sh && \
    sed -i  's@^export SWIFT_T_PREFIX=.*@export SWIFT_T_PREFIX=/opt/swift-t@' ./swift-t-1.4/dev/build/swift-t-settings.sh && \
    sed -i  's@.*ENABLE_PYTHON=1@ENABLE_PYTHON=1@' ./swift-t-1.4/dev/build/swift-t-settings.sh && \
    sed -i  's@.*ENABLE_R=1@ENABLE_R=1@' ./swift-t-1.4/dev/build/swift-t-settings.sh && \
    sed -i  's@.*R_INSTALL=.*@R_INSTALL=/usr/share/R/@' ./swift-t-1.4/dev/build/swift-t-settings.sh && \
    $BUILD_DIR/swift-t-1.4/dev/build/build-all.sh

ENV TURBINE_PATH="${BUILD_DIR}/swift-t/turbine"
RUN chmod +x $TURBINE_PATH/bin/turbine && \
    sed -i  's@\${TURBINE_LAUNCHER} \${OPTIONS} \${=VALGRIND} @\${TURBINE_LAUNCHER} \${OPTIONS} \${=VALGRIND} \${TURBINE_HOME}/bin/gpurunscript.sh @' $TURBINE_PATH/bin/turbine && \
    cp /gpurunscript.sh $TURBINE_PATH/bin && \
    chmod +x $TURBINE_PATH/bin/gpurunscript.sh

ENV PATH="${BUILD_DIR}/swift-t/stc/bin/:${TURBINE_PATH}/bin:${PATH}"
ENV TURBINE_LAUNCH_OPTIONS --allow-run-as-root

RUN git clone https://github.com/emews/EQ-R.git
WORKDIR $BUILD_DIR/EQ-R/src

RUN ./bootstrap
RUN cp settings.template.sh settings.sh
RUN sed -i 's@^R_LOCAL_LIB=.*@R_LOCAL_LIB=/usr/local/lib/R/site-library@' ./settings.sh && \
    sed -i 's@^TCL_INCLUDE=.*@TCL_INCLUDE=/usr/include/tcl@' ./settings.sh && \
    sed -i 's@^TCL_LIB=.*@TCL_LIB=/usr/lib@' ./settings.sh && \
    bash -c 'source settings.sh && ./configure --prefix=/opt/EQ-R && make install && make clean'

WORKDIR /opt
RUN git clone https://github.com/ECP-CANDLE/Benchmarks.git && \
    cd Benchmarks && git checkout frameworks

RUN mkdir -p /opt/Benchmarks/Data/Pilot1/ && \
    mkdir /opt/Benchmarks/Data/P3B1/

# The CANDLE Benchmarks check the Benchmarks/Data directory for the
# corresponding benchmark data at run time. If the data does not exist it
# is downladed from the ftp.mcs.anl.gov URL. This will fail on systems 
# or compute nodes that do not have network access at run time. We provide
# the necessary benchmark data to run the example workflow on machines 
# independent of network connectivity at run time.
WORKDIR /opt/Benchmarks/Data/Pilot1
RUN wget http://ftp.mcs.anl.gov/pub/candle/public/benchmarks/P1B1/P1B1.dev.train.csv && \
    wget http://ftp.mcs.anl.gov/pub/candle/public/benchmarks/P1B1/P1B1.dev.test.csv && \
    wget http://ftp.mcs.anl.gov/pub/candle/public/benchmarks/Pilot1/normal-tumor/nt_train2.csv && \
    wget http://ftp.mcs.anl.gov/pub/candle/public/benchmarks/Pilot1/normal-tumor/nt_test2.csv

WORKDIR /opt/Benchmarks/Data/P3B1
RUN wget http://ftp.mcs.anl.gov/pub/candle/public/benchmarks/P3B1/P3B1_data.tar.gz

# Download the CANDLE/Tutortial and configure the workslow script to run 
# against the Pilot3/P3B1 data.
WORKDIR /opt
RUN git clone https://github.com/ECP-CANDLE/Tutorials.git
WORKDIR /opt/Tutorials/2018/NIH/Supervisor
RUN sed -i 's@PYTHONPATH=$HOME/proj*@PYTHONPATH=/opt@' model.sh && \
    sed -i 's@.*EQR=$EMEWS_PROJECT_ROOT/EQ-R@EQR=/opt/EQ-R@' workflow.sh && \
    sed -i 's@.*R=$HOME@#R=$HOME@' workflow.sh && \
    sed -i 's@.*LD_LIBRARY_PATH@#LD_LIBRARY_PATH@' workflow.sh && \
    sed -i 's@.*PROCS=3@PROCS=6@' workflow.sh
