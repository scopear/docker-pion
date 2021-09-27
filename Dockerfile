ARG OS_NAME=debian
ARG OS_VERSION=latest

# ===
# Install golang (not new enough from offical build) and build the binaries 
FROM ${OS_NAME}:${OS_VERSION} as golang-base
ARG GOLANG_VERSION=go1.17.1 

RUN set -eux \
  && apt-get upgrade && apt-get update \
  && apt-get install -y bash openssl tar gzip wget \
  && echo "Downloading golang version=${GOLANG_VERSION}" \
  && mkdir -p /build-temp \
  && wget -O /build-temp/golang.tar.gz "https://dl.google.com/go/${GOLANG_VERSION}.linux-amd64.tar.gz" \
  && tar -xf /build-temp/golang.tar.gz -C /usr/local \
  && export PATH="/usr/local/go/bin:$PATH" \
  && go version && which go


# ===
# Install golang and build the binaries 
FROM ${OS_NAME}:${OS_VERSION} as custom-binaries

COPY --from=golang-base /usr/local/go /usr/local/
ARG PATH="/usr/local/go/bin:$PATH"
ENV PATH="/usr/local/go/bin:$PATH"

RUN set -eux \
  && apt-get upgrade && apt-get update \
  && apt-get install -y ca-certificates && update-ca-certificates

# Create a working directory
RUN mkdir -p /build-temp
COPY  ./ /build-temp

# Build the custom-pion binaries
RUN cd /build-temp/custom-pion/server \
    && go build -o /usr/local/bin/pion-server \
    && cd /build-temp/custom-pion/client \
    && go build -o /usr/local/bin/pion-client \
    && chmod +x /usr/local/bin/pion-server \
    && chmod +x /usr/local/bin/pion-client

# Make binaries executable
RUN chmod +x /build-temp/custom-pion/run_pion \
    && chmod +x /build-temp/custom-pion/health_check


# ---
# Final Image with essentials only
FROM ${OS_NAME}:${OS_VERSION}

RUN apt-get upgrade && apt-get update \
	&& apt-get install -y bash

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