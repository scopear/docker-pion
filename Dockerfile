FROM alpine:latest

RUN apk update && apk add --no-cache git make musl-dev bash curl tar go gcc musl-dev openssl-dev ca-certificates && update-ca-certificates

# Install golang
# You can find the latest golang version with `curl https://golang.org/VERSION?m=text`
ARG GO_VERSION=go1.17.1 
RUN echo "Downloading golang version=${GO_VERSION}" \
  && wget "https://dl.google.com/go/${GO_VERSION}.linux-amd64.tar.gz" -O - | tar -xz -C /usr/local \
  && cd /usr/local/go/src && ./make.bash \
  && go version \
  && apk del go
ENV PATH=$PATH:/usr/local/go/bin

# Build the custom-pion binaries
RUN /build-temp
COPY  ./ /build-temp
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