FROM alpine:3.4
MAINTAINER Reid Priedhorsky <reidpr@lanl.gov>

RUN apk add --no-cache gcc make musl-dev python3

COPY test/chtest test
WORKDIR /test
RUN make -j$(getconf _NPROCESSORS_ONLN)

CMD ["true"]
