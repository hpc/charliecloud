FROM alpine:3.5
MAINTAINER Reid Priedhorsky <reidpr@lanl.gov>

RUN apk add --no-cache gcc make musl-dev python3

COPY test/chtest test
WORKDIR /test
RUN make -j$(getconf _NPROCESSORS_ONLN)

# Create sentinel file for --no-home --bind tests
RUN echo > /home/foo

CMD ["true"]
