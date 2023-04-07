# Skip this test because of issues with gcr.io (see #896).
# ch-test-scope: skip
# ch-test-arch-exclude: ppc64le  # base image unavailable
# Distroless is a Google project providing slim images that contain runtime
# dependencies only. https://github.com/GoogleContainerTools/distroless
# The python3 image was chosen for ease of testing.
FROM gcr.io/distroless/python3
COPY hello.py /
