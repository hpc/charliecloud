FROM rocker/verse:3.6.1

RUN apt-get update \
  && apt-get install -y --no-install-recommends \ 
     python3 \
     python3-pip \
     firefox-esr \ 
     imagemagick \
     strace \
     wget 

RUN pip3 install selenium

# Need to install newest version of geckodriver for selenium
ARG GECKODRIVER_VERSION=v0.30.0
RUN wget https://github.com/mozilla/geckodriver/releases/download/$GECKODRIVER_VERSION/geckodriver-v0.30.0-linux32.tar.gz
RUN tar xvf geckodriver-$GECKODRIVER_VERSION-linux32.tar.gz -C /usr/bin/ && \
                rm geckodriver-$GECKODRIVER_VERSION-linux32.tar.gz

COPY start_rstudio rstudio_auth run.py test_rstudio.py model.R /rstudio 
