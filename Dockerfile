ARG OS_NAME=alpine
ARG OS_VERSION=latest

# ===
# Install golang and build the binaries 
FROM golang:alpine as builder

RUN apk update && apk add --no-cache git

# Create a working directory
RUN mkdir -p /build-temp
COPY  ./ /build-temp

# Build the custom-pion binaries
RUN cd /build-temp/custom-pion/server \
    && go build -o /go/bin/pion-server \
    && cd /build-temp/custom-pion/client \
    && go build -o /go/bin/pion-client \
    && chmod +x /go/bin/pion-server \
    && chmod +x /go/bin/pion-client

# Make binaries executable
RUN chmod +x /build-temp/custom-pion/run_pion \
    && chmod +x /build-temp/custom-pion/health_check


# ---
# Final Image with essentials only
FROM scratch

# Copy binaries
COPY --from=builder /go/bin/pion-server /go/bin/pion-server
COPY --from=builder /go/bin/pion-client /go/bin/pion-client

# Copy custom scripts
# COPY --from=builder /build-temp/custom-pion/run_pion /usr/local/bin/run_pion
# COPY --from=builder /build-temp/custom-pion/health_check /usr/local/bin/health_check

#USER 65534

# HEALTHCHECK --start-period=30s --interval=1m --timeout=30s \
#   CMD /usr/local/bin/health_check

ENTRYPOINT ["/usr/local/bin/run_pion"]