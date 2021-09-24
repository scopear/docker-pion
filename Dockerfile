ARG DEBIAN_VERSION=latest

# ===
# Install golang (not new enough from offical build) and build the binaries 
FROM alpine:${DEBIAN_VERSION} as golang-base
ARG GOLANG_VERSION=go1.17.1 

RUN set -eux \
  && apk add --no-cache --virtual .build-deps bash gcc musl-dev openssl go \
	&& export \
    # set GOROOT_BOOTSTRAP such that we can actually build Go
		GOROOT_BOOTSTRAP="$(go env GOROOT)" \
    # ... and set "cross-building" related vars to the installed system's values so that we create a build targeting the proper arch
    # (for example, if our build host is GOARCH=amd64, but our build env/image is GOARCH=386, our build needs GOARCH=386)
		GOOS="$(go env GOOS)" \
		GOARCH="$(go env GOARCH)" \
		GOHOSTOS="$(go env GOHOSTOS)" \
		GOHOSTARCH="$(go env GOHOSTARCH)" \

    # also explicitly set GO386 and GOARM if appropriate
    # https://github.com/docker-library/golang/issues/184
	  && apkArch="$(apk --print-arch)" \
    && case "$apkArch" in \
      armhf) export GOARM='6' ;; \
      x86) export GO386='387' ;; \
    esac \
	&& echo "Downloading golang version=${GOLANG_VERSION}" \
  && wget "https://dl.google.com/go/${GOLANG_VERSION}.linux-amd64.tar.gz" -O - | tar -xz -C /usr/local \
	&& cd /usr/local/go/src \
	&& ./make.bash \
	&& rm -rf \
    # https://github.com/golang/go/blob/0b30cf534a03618162d3015c8705dd2231e34703/src/cmd/dist/buildtool.go#L121-L125
		/usr/local/go/pkg/bootstrap \
    # https://golang.org/cl/82095
    # https://github.com/golang/build/blob/e3fe1605c30f6a3fd136b561569933312ede8782/cmd/release/releaselet.go#L56
		/usr/local/go/pkg/obj \
	&& apk del .build-deps \
	&& export PATH="/usr/local/go/bin:$PATH" \
	&& go version && which go
  
ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"
WORKDIR $GOPATH


# ===
# Install golang and build the binaries 
FROM alpine:${DEBIAN_VERSION} as custom-binaries

COPY --from=golang-base /usr/local/go /usr/local/
ARG PATH="/usr/local/go/bin:$PATH"
ENV PATH="/usr/local/go/bin:$PATH"

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
FROM alpine:${DEBIAN_VERSION}

RUN apk add --no-cache bash

# Copy golang
COPY --from=golang-base /usr/local/go /usr/local/

# Copy binaries
COPY --from=custom-binaries /usr/local/bin/pion-server /usr/local/bin/pion-server
COPY --from=custom-binaries /usr/local/bin/pion-client /usr/local/bin/pion-client

# Copy custom scripts
COPY --from=custom-binaries /build-temp/custom-pion/run_pion /usr/local/bin/run_pion
COPY --from=custom-binaries /build-temp/custom-pion/health_check /usr/local/bin/health_check

# Set the go path
ARG PATH="/usr/local/go/bin:$PATH"
ENV PATH="/usr/local/go/bin:$PATH"

USER 65534

HEALTHCHECK --start-period=30s --interval=1m --timeout=30s \
  CMD /usr/local/bin/health_check

ENTRYPOINT ["/usr/local/bin/run_pion"]