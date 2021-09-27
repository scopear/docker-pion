ARG OS_NAME=alpine
ARG OS_VERSION=latest

# ===
# Install golang and build the binaries 
FROM golang:alpine as builder

RUN apk update && apk upgrade && apk add --no-cache git bash

WORKDIR $GOPATH/src/mypackage/myapp/

# Create a working directory
RUN mkdir -p /build-temp
COPY  ./ /build-temp

# Build the custom-pion binaries
RUN cd /build-temp/custom-pion/server \
    && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /go/bin/pion-server \
    && cd /build-temp/custom-pion/client \
    && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /go/bin/pion-client \
    && chmod +x /go/bin/pion-server \
    && chmod +x /go/bin/pion-client

# ---
# Final Image with essentials only
FROM scratch

# Copy Bash
COPY --from=builder /bin/sh /bin/sh
COPY --from=builder /bin/bash /bin/bash

# Copy binaries
COPY --from=builder /go/bin/pion-server /go/bin/pion-server
COPY --from=builder /go/bin/pion-client /go/bin/pion-client

USER 65534

HEALTHCHECK --start-period=30s --interval=1m --timeout=30s \
  CMD bash -c /go/bin/pion-client \
  	-host $TURN_EXTERNAL_IPV4 \
    -realm $TURN_REALM_NAME \
    -port $TURN_SERVER_PORT \
    -user $TURN_USER_NAME=$TURN_USER_PASSWORD

ENTRYPOINT bash -c /go/bin/pion-server \
	-public-ip $TURN_EXTERNAL_IPV4 \
	-port $TURN_SERVER_PORT \
	-users $TURN_USER_NAME=$TURN_USER_PASSWORD \
	-realm $TURN_REALM_NAME \
	-port-range-min $TURN_RELAY_PORT_RANGE_MIN \
	-port-range-max $TURN_RELAY_PORT_RANGE_MAX