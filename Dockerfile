FROM alpine:latest

RUN apk add --no-cache git make musl-dev go bash

# Configure Go
ENV GOROOT /usr/lib/go
ENV GOPATH /go
ENV PATH /go/bin:$PATH

RUN mkdir -p ${GOPATH}/src ${GOPATH}/bin  /build-temp

COPY  ./ /build-temp

# Build the custom-pion binary
RUN cd /build-temp/custom-pion/server && \
    go build -o /usr/local/bin/pion-server && \
    cd /build-temp/custom-pion/client && \
    go build -o /usr/local/bin/pion-client && \
    cp /build-temp/custom-pion/run_pion /usr/local/bin/run_pion && \
    chmod +x /usr/local/bin/pion-server /usr/local/bin/pion-client && \
    rm -rf /build-temp

USER 65534

ENTRYPOINT ["/usr/local/bin/run_pion"]