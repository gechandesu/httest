FROM debian:trixie AS vlang
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install --assume-yes --no-install-recommends --no-install-suggests ca-certificates git build-essential && \
    apt-get clean
RUN git clone --depth=1 https://github.com/vlang/v /opt/v && make -C /opt/v && /opt/v/v symlink && v version

FROM vlang AS builder
COPY . .
RUN v install
RUN v -prod -cflags '-static -s' -d version="$(git describe HEAD)+$(v version | tr ' ' '-')" . -o /httest

FROM scratch AS prod
COPY --from=builder /httest .
ENTRYPOINT ["/httest"]
