# ch-test-scope: standard
FROM gcr.io/distroless/python3
COPY . /distroless

# Without the CMD directive ch-builder2tar will fail when using docker
CMD ["/distroless/hello.py"]
