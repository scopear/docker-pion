ARG DEBIAN_VERSION=latest

# ===
# Install golang and build the binaries 
FROM ubuntu:${DEBIAN_VERSION} as base
ARG GO_VERSION=go1.17.1 

# Install golang
# You can find the latest golang version with `curl https://golang.org/VERSION?m=text`
RUN apt-get update && apt-get install -y wget tar git make musl-dev bash coreutils
RUN echo "Downloading golang version=${GO_VERSION}" \
  && wget "https://dl.google.com/go/${GO_VERSION}.linux-amd64.tar.gz" -O - | tar -xz -C /usr/local \
  && cd /usr/local/go/src/ \
  && export PATH=$PATH:/usr/local/go/bin \
  && go version
ARG PATH=$PATH:/usr/local/go/bin 
ENV PATH=$PATH:/usr/local/go/bin 

# Create a working directory
RUN mkdir -p /build-temp
COPY  ./ /build-temp

# Build the custom-pion binaries
RUN cd /build-temp/custom-pion/server && \
    go build -o /usr/local/bin/pion-server && \
    cd /build-temp/custom-pion/client && \
    go build -o /usr/local/bin/pion-client && \
    chmod +x /usr/local/bin/pion-server && \
    chmod +x /usr/local/bin/pion-client

# Make binaries executable
RUN chmod +x /build-temp/custom-pion/run_pion && \
    chmod +x /build-temp/custom-pion/health_check


# ---
# Final Image with essentials only
FROM ubuntu:${DEBIAN_VERSION}

# Copy golang
COPY --from=base /usr/local/go /usr/local/

# Copy binaries
COPY --from=base /usr/local/bin/pion-server /usr/local/bin/pion-server
COPY --from=base /usr/local/bin/pion-client /usr/local/bin/pion-client

# Copy custom scripts
COPY --from=base /build-temp/custom-pion/run_pion /usr/local/bin/run_pion
COPY --from=base /build-temp/custom-pion/health_check /usr/local/bin/health_check

# Set the go path
ENV PATH=$PATH:/usr/local/go/bin

RUN apt-get update && apt-get install -y bash

USER 65534

HEALTHCHECK --start-period=30s --interval=1m --timeout=30s \
  CMD /usr/local/bin/health_check

ENTRYPOINT ["/usr/local/bin/run_pion"]