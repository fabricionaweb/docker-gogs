# syntax=docker/dockerfile:1-labs
FROM public.ecr.aws/docker/library/alpine:3.19 AS base
ENV TZ=UTC
WORKDIR /src

# source stage =================================================================
FROM base AS source

# get and extract source from git
ARG BRANCH
ARG VERSION
ADD https://github.com/gogs/gogs.git#${BRANCH:-v$VERSION} ./

# build stage ==================================================================
FROM base AS build-backend
# required for go-sqlite3
ENV CGO_ENABLED=1 CGO_CFLAGS="-D_LARGEFILE64_SOURCE"

# dependencies
RUN apk add --no-cache build-base git && \
    apk add --no-cache go --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community

# build dependencies
COPY --from=source /src/go.mod /src/go.sum ./
RUN go mod download

# build app
COPY --from=source /src ./
ARG VERSION
ARG COMMIT=$VERSION
RUN mkdir /build && \
    go build -trimpath -ldflags "-s -w \
        -X gogs.io/gogs/internal/conf.BuildCommit=$COMMIT \
        -X gogs.io/gogs/internal/conf.BuildTime=$(date -u '+%Y-%m-%d_%I:%M:%S%p')" \
        -o /build/

# runtime stage ================================================================
FROM base

ENV S6_VERBOSITY=0 S6_BEHAVIOUR_IF_STAGE2_FAILS=2 PUID=65534 PGID=65534
ENV GOGS_CUSTOM=/config
WORKDIR /config
VOLUME /config
EXPOSE 2222 3000

# copy files
COPY --from=build-backend /build /app
COPY ./rootfs/. /

# runtime dependencies
RUN apk add --no-cache openssh-server shadow tzdata s6-overlay curl git && \
    apk add --no-cache gosu --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing

# run using s6-overlay
ENTRYPOINT ["/entrypoint.sh"]
