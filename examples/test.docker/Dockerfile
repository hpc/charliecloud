# Image suitable for testing. Build with (note trailing dot):
#
#   $ sudo docker build -t $USER/chtest --build-arg HTTP_PROXY=$HTTP_PROXY --build-arg HTTPS_PROXY=$HTTPS_PROXY --build-arg http_proxy=$http_proxy --build-arg https_proxy=$https_proxy --build-arg no_proxy=$no_proxy .
#
# Start container and get a shell:
#
#   $ sudo docker -it $USER/chtest
#
# Start container and run a different, non-interactive command:
#
#   $ sudo docker $USER/chtest ps aux

FROM debian:jessie
MAINTAINER Reid Priedhorsky <reidpr@lanl.gov>

# add python 3
RUN apt-get update && apt-get install -y \
    python3

# add a suid link to bash to test privilege escalation
RUN cp /bin/bash /bin/bash.setuid && chmod 4755 /bin/bash.setuid

# default command is just a shell
CMD ["/bin/bash"]
