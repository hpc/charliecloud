# ch-test-builder-include: ch-image
FROM alpine:3.17
RUN apk add gcc musl-dev strace
RSYNC / /
RUN gcc -std=c11 -Wall -Werror -fmax-errors=1 -o mknods mknods.c
RUN strace ./mknods
RUN ls -lh /_*
RUN test $(ls /_* | wc -l) == 2
RUN test -p /_mknod_fifo
RUN test -p /_mknodat_fifo
