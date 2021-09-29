FROM rocker/verse:3.6.1

RUN apt-get update \
  && apt-get install -y --no-install-recommends \ 
     python3 \
     python3-pip \
     firefox-esr \ 
     imagemagick \
     wget 


RUN pip3 install selenium

# Need to install newest version of geckodriver for selenium
RUN wget https://github.com/mozilla/geckodriver/releases/download/v0.30.0/geckodriver-v0.30.0-linux32.tar.gz
RUN tar xvf geckodriver-v0.30.0-linux32.tar.gz -C /usr/bin/ && \
                rm geckodriver-v0.30.0-linux32.tar.gz


COPY start_rstudio /bin/start_rstudio
RUN chmod +x /bin/start_rstudio

COPY rstudio_auth /bin/rstudio_auth
RUN chmod +x /bin/rstudio_auth

COPY compare.sh .
COPY test_rstudio.py .
COPY model.R .
