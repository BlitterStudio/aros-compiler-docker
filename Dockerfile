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
# What ships in the image:
#   - AROS cross-compiler (gcc/binutils) + SDK (libs + headers)
#   - xadmaster.library headers from AROS-Contrib (so xadmaster-using
#     modules like dopus5's xadopus.module can be cross-compiled)
#   - LHa for UNIX 1.14i-ac (full read/write LHA tool, needed to
#     produce .lha release archives)
#
# Usage:
#   docker build -t midwan/aros-compiler:i386-aros   --build-arg aros_target=i386-aros .
#   docker build -t midwan/aros-compiler:x86_64-aros --build-arg aros_target=x86_64-aros .
#
#   docker run --rm -it -v <path-to-dopus5-sources>:/work midwan/aros-compiler:i386-aros

ARG ubuntu_release=24.04
ARG aros_target=i386-aros
ARG aros_repo=https://github.com/deadwood2/AROS.git
# AROS-Contrib provides workbench/libs/xad/portable, which is what we
# fish the xadmaster.library headers out of. The repo lives at the
# AROS development team's contrib repo; we clone it as a sibling
# subdirectory of the AROS source so the AROS build system finds it
# at the conventional $(AROSDIR)/contrib path.
ARG aros_contrib_repo=https://github.com/aros-development-team/contrib.git
# LHa for UNIX 1.14i-ac (Koji Arai's autotools fork). Pinned via tag so
# image rebuilds are reproducible. This is the same tool sacredbanana's
# m68k/ppc Amiga images ship; the binary reports as
# `LHa for UNIX version 1.14i-ac<date>` regardless of which release is
# checked out, so AROS .lha release archives come out byte-comparable
# with the m68k/ppc archives.
ARG lha_repo=https://github.com/jca02266/lha.git
ARG lha_ref=release-20211125

############################
# Stage 1: builder
############################
FROM ubuntu:${ubuntu_release} AS builder

ARG aros_target
ARG aros_repo
ARG aros_contrib_repo
ARG lha_repo
ARG lha_ref

ENV DEBIAN_FRONTEND=noninteractive

# Union of build deps from deadwood2 INSTALL.md (alt-abiv0 + master
# branches) plus libtool/perl for the LHa for UNIX autoreconf bootstrap.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git make gcc g++ gawk bison flex bzip2 \
        netpbm autoconf automake libtool perl \
        libx11-dev libxext-dev libc6-dev liblzo2-dev libxxf86vm-dev \
        libpng-dev gcc-multilib libsdl1.2-dev byacc python3-mako \
        libxcursor-dev cmake genisoimage dh-make yasm nasm \
        unzip xorriso mtools mingw-w64 zsh && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/aros-work

# Build LHa for UNIX 1.14i-ac and stash the binary under /opt/lha-bin
# for the runtime stage. Doing it here (in the builder) keeps the
# autotools / libtool deps off the runtime image.
RUN set -eux; \
    git clone --depth 1 --branch "${lha_ref}" "${lha_repo}" /tmp/lha-src; \
    cd /tmp/lha-src; \
    aclocal && autoheader && automake --add-missing --foreign && autoconf; \
    ./configure --prefix=/opt/lha-bin; \
    make -j "$(nproc)"; \
    make install; \
    /opt/lha-bin/bin/lha 2>&1 | head -2; \
    rm -rf /tmp/lha-src

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
#
# AROS-Contrib is cloned as $(AROSDIR)/contrib so the AROS build system
# picks it up at the conventional location.  After the SDK is in place we
# add a `make xadmaster-includes` pass to install the xadmaster.library
# headers (proto/, inline/, clib/, libraries/) into the SDK.
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
            sdk_make_args=""; \
            need_reconfigure=yes; \
            ;; \
        *) echo "Unknown aros_target=${aros_target}" >&2; exit 1;; \
    esac; \
    git clone --depth 1 --branch "${branch}" "${aros_repo}" /opt/aros-work/AROS; \
    # Sparse-clone of AROS-Contrib pulling only workbench/libs/xad (~6 MB
    # vs 175 MB for the full repo).  The full Contrib tree contains
    # several modules with mmakefile.src files that are broken against
    # current AROS master/alt-abiv0 (SDL/SDL_main, regina, scout, ...);
    # cloning everything makes `make crosstools` fail at the mmake-scan
    # step regardless of whether we ever build those modules.  We only
    # need workbench/libs/xad for xadmaster.library, so we pull that
    # subtree and let mmake walk a clean Contrib.
    git clone --depth 1 --filter=blob:none --sparse \
        "${aros_contrib_repo}" /opt/aros-work/AROS/contrib && \
    git -C /opt/aros-work/AROS/contrib sparse-checkout set workbench/libs/xad; \
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
    # Install xadmaster.library headers from AROS-Contrib's portable
    # xad port. The %build_module macro in
    # contrib/workbench/libs/xad/portable/mmakefile.src generates an
    # `xadmaster-includes` mmake target that installs proto/inline/clib/
    # libraries headers into the SDK include tree without doing the
    # full library build.
    make xadmaster-includes -j "$(nproc)"; \
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
LABEL org.opencontainers.image.description="AROS cross-compiler toolchain (${aros_target}) with xadmaster headers + LHa for UNIX"
LABEL org.opencontainers.image.authors="Dimitris Panokostas"
LABEL org.opencontainers.image.source="https://github.com/BlitterStudio/aros-compiler-docker"
LABEL org.opencontainers.image.licenses="GPL-3.0"

# Runtime deps: make + gawk are needed by the dopus5 makefile.
# `lha` comes from /opt/lha-bin built in the builder stage; we no longer
# install lhasa from apt because it cannot create archives (only extract).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates make gawk file && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/aros-toolchain /opt/aros-toolchain
COPY --from=builder /opt/aros-build /opt/aros-build
COPY --from=builder /opt/lha-bin /opt/lha-bin

# AROS' --with-aros-toolchain-install layout places the cross binaries
# directly in the install root (e.g. /opt/aros-toolchain/i386-aros-gcc),
# not under a bin/ subdirectory. /opt/lha-bin/bin holds the `lha` binary
# built from jca02266/lha in the builder stage.
ENV PATH=/opt/aros-toolchain:/opt/lha-bin/bin:$PATH

WORKDIR /work

CMD ["bash"]
