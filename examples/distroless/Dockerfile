# ch-test-scope: standard
# Distroless is a Google project providing slim images that contain runtime
# dependencies only. https://github.com/GoogleContainerTools/distroless
# The python3 image was chosen for ease of testing.
FROM gcr.io/distroless/python3
COPY hello.py /

# Without the CMD directive ch-builder2tar will fail when using docker
CMD ["/hello.py"]
