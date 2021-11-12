# Rocker appears to be the most popular R Docker images, though they’re not
# “official” on Docker Hub. See: https://www.rocker-project.org/images/
FROM rocker/rstudio:4.1.2

RUN apt-get update
RUN apt-get install -y --no-install-recommends \
    firefox-geckodriver \
    imagemagick \
    python3-pip \
    strace

RUN pip3 install selenium

COPY . /rstudio
