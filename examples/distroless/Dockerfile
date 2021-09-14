# ch-test-scope: standard
# Distroless is a Google project providing slim images that contain runtime
# dependencies only. https://github.com/GoogleContainerTools/distroless
FROM gcr.io/distroless/python3
COPY . /distroless

# Without the CMD directive ch-builder2tar will fail when using docker
CMD ["/distroless/hello.py"]
