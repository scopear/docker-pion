FROM golang:latest

RUN apt-get update && apt-get -y install git make musl-dev bash

# Configure Go
# ENV GOROOT /usr/lib/go
# ENV GOPATH /go
# ENV PATH /go/bin:$PATH

RUN mkdir -p /build-temp

COPY  ./ /build-temp

# Build the custom-pion binaries
RUN cd /build-temp/custom-pion/server && \
    go build -o /usr/local/bin/pion-server && \
    cd /build-temp/custom-pion/client && \
    go build -o /usr/local/bin/pion-client && \
    chmod +x /usr/local/bin/pion-server && \
    chmod +x /usr/local/bin/pion-client

# Copy over scripts
RUN cp /build-temp/custom-pion/run_pion /usr/local/bin/run_pion && \
    cp /build-temp/custom-pion/health_check /usr/local/bin/health_check && \
    chmod +x /usr/local/bin/run_pion && \
    chmod +x /usr/local/bin/health_check
    
# Clean up 
RUN rm -rf /build-temp

USER 65534

HEALTHCHECK --start-period=30s --interval=1m --timeout=30s \
  CMD /usr/local/bin/health_check

ENTRYPOINT ["/usr/local/bin/run_pion"]