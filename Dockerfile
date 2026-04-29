# AROS cross-compiler image
# Author: Dimitris Panokostas
#
# Build args:
#   aros_target    - "i386-aros" (ABIv0, alt-abiv0 branch)
#                    "x86_64-aros" (ABIv11, master branch)
#   ubuntu_release - Ubuntu base image tag (default: 24.04)
#
# The resulting image places the AROS cross-toolchain on PATH so
# `${arch}-aros-gcc` is directly invokable. Source/build trees are
# discarded in the final stage to keep the image small.
#
# Usage:
#   docker build -t midwan/aros-compiler:i386-aros   --build-arg aros_target=i386-aros .
#   docker build -t midwan/aros-compiler:x86_64-aros --build-arg aros_target=x86_64-aros .
#
#   docker run --rm -it -v <path-to-dopus5-sources>:/work midwan/aros-compiler:i386-aros

ARG ubuntu_release=24.04
ARG aros_target=i386-aros
ARG aros_repo=https://github.com/deadwood2/AROS.git

############################
# Stage 1: builder
############################
FROM ubuntu:${ubuntu_release} AS builder

ARG aros_target
ARG aros_repo

ENV DEBIAN_FRONTEND=noninteractive

# Union of build deps from deadwood2 INSTALL.md (alt-abiv0 + master branches).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git make gcc g++ gawk bison flex bzip2 \
        netpbm autoconf automake \
        libx11-dev libxext-dev libc6-dev liblzo2-dev libxxf86vm-dev \
        libpng-dev gcc-multilib libsdl1.2-dev byacc python3-mako \
        libxcursor-dev cmake genisoimage dh-make yasm nasm \
        unzip xorriso mtools mingw-w64 zsh && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/aros-work

# Build directly into the final runtime paths so the install/build locations
# baked into the cross-gcc spec (used to find ld/as and the SDK sysroot) are
# valid in the runtime image without any post-build copying.
#
# Branch / SDK target choice mirrors deadwood2/AROS rebuild.sh selections:
#   - alt-abiv0 has a clean `make sdk` after `make crosstools` (selection 1)
#   - master needs a full AROS build to populate collect-aros + linklibs
#     (selection 1 builds the toolchain, selection 2 builds AROS itself
#     using --with-aros-toolchain=yes). We replicate that two-phase flow
#     in a single build tree by re-running configure with the flag set
#     before the AROS build.
RUN set -eux; \
    case "${aros_target}" in \
        i386-aros) \
            branch=alt-abiv0; \
            cfg_target=linux-i386; \
            sdk_make_args="-s sdk"; \
            need_reconfigure=no; \
            ;; \
        x86_64-aros) \
            branch=master; \
            cfg_target=linux-x86_64; \
            sdk_make_args="-s"; \
            need_reconfigure=yes; \
            ;; \
        *) echo "Unknown aros_target=${aros_target}" >&2; exit 1;; \
    esac; \
    git clone --depth 1 --branch "${branch}" "${aros_repo}" /opt/aros-work/AROS; \
    mkdir -p /opt/aros-toolchain /opt/aros-build /opt/aros-work/portssources; \
    cd /opt/aros-build; \
    /opt/aros-work/AROS/configure \
        --target=${cfg_target} \
        --with-aros-toolchain-install=/opt/aros-toolchain \
        --with-portssources=/opt/aros-work/portssources; \
    make -s crosstools -j "$(nproc)"; \
    if [ "${need_reconfigure}" = "yes" ]; then \
        /opt/aros-work/AROS/configure \
            --target=${cfg_target} \
            --with-aros-toolchain=yes \
            --with-aros-toolchain-install=/opt/aros-toolchain \
            --with-portssources=/opt/aros-work/portssources; \
    fi; \
    make ${sdk_make_args} -j "$(nproc)"; \
    # Strip the build dir to just the Development sysroot (the only part
    # gcc references at runtime) and discard the AROS source / port sources.
    mv /opt/aros-build/bin/${cfg_target}/AROS/Development /tmp/aros-dev-keep; \
    rm -rf /opt/aros-build /opt/aros-work; \
    mkdir -p /opt/aros-build/bin/${cfg_target}/AROS; \
    mv /tmp/aros-dev-keep /opt/aros-build/bin/${cfg_target}/AROS/Development

############################
# Stage 2: runtime
############################
FROM ubuntu:${ubuntu_release}

ARG aros_target
ENV DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="AROS cross-compiler"
LABEL org.opencontainers.image.description="AROS cross-compiler toolchain (${aros_target})"
LABEL org.opencontainers.image.authors="Dimitris Panokostas"
LABEL org.opencontainers.image.source="https://github.com/BlitterStudio/aros-compiler-docker"
LABEL org.opencontainers.image.licenses="GPL-3.0"

# Runtime deps: make + gawk are needed by the dopus5 makefile, lhasa
# provides the `lha` command used to build release archives.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates make gawk lhasa file && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/aros-toolchain /opt/aros-toolchain
COPY --from=builder /opt/aros-build /opt/aros-build

# AROS' --with-aros-toolchain-install layout places the cross binaries
# directly in the install root (e.g. /opt/aros-toolchain/i386-aros-gcc),
# not under a bin/ subdirectory.
ENV PATH=/opt/aros-toolchain:$PATH

WORKDIR /work

CMD ["bash"]
