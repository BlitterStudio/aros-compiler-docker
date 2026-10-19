# aros-compiler-docker

Docker image with AROS cross-toolchains, used to build software targeting AROS from any Linux x86_64 host (including GitHub Actions runners). The i386 (ABIv0) and x86_64 (ABIv11) images use GCC; the ARM64/aarch64 (ABIv11, Raspberry Pi) image uses Clang 18 to compile and AROS' C `collect-aros` to link.

The image is published on Docker Hub: <https://hub.docker.com/r/midwan/aros-compiler>

## What's inside

- i386 and x86_64: AROS GCC/binutils cross-toolchain with the AROS SDK (libs + headers) baked into the GCC spec.
- aarch64: stock Ubuntu 24.04 Clang 18 (`clang-18`, also available as `clang`), plus the AROS SDK, target binutils, and C `collect-aros`. Clang emits AROS-targeted object code; `collect-aros` links it using the SDK and target binutils.
- **xadmaster.library headers** from [AROS-Contrib](https://github.com/aros-development-team/contrib) — sources that include `<proto/xadmaster.h>` (e.g. dopus5's `xadopus.module`) cross-compile out of the box.
- **LHa for UNIX 1.14i-ac** ([jca02266/lha](https://github.com/jca02266/lha)) — the full read/write LHA tool, so AROS makefiles that produce `.lha` release archives work without falling back to a separate "packager" image.
- `make`, `gawk`, `file` — the rest of the dopus5 makefile's runtime requirements.

## Tags

| Tag | AROS variant | Branch | Compiler and linker |
|---|---|---|---|
| `i386-aros` | ABIv0 (legacy) | [`deadwood2/AROS` `alt-abiv0`](https://github.com/deadwood2/AROS/tree/alt-abiv0) | `i386-aros-gcc` |
| `x86_64-aros` | ABIv11 (modern) | [`deadwood2/AROS` `master`](https://github.com/deadwood2/AROS) | `x86_64-aros-gcc` |
| `aarch64-aros` | ABIv11 (ARM64) | [`aros-development-team/AROS` `master`](https://github.com/aros-development-team/AROS) | `clang-18 --target=aarch64-aros` (or `clang --target=aarch64-aros`); `collect-aros` |

The `i386-aros` toolchain produces binaries compatible with the AROS distributions most users run today (Icaros Desktop, AROS One). The `x86_64-aros` toolchain targets modern ABIv11 AROS. The `aarch64-aros` toolchain targets the ARM64 Raspberry Pi port used by the [raspi-aarch64 nightlies](https://sourceforge.net/projects/aros/files/nightly2/) (Raspberry Pi 3/4/5 in 64-bit mode).

## Usage

Run an i386 or x86_64 image and invoke its GCC cross-compiler directly:

```bash
docker run --rm -it -v <dir-with-your-sources>:/work midwan/aros-compiler:i386-aros
i386-aros-gcc source.c -o program
```

For aarch64, compile with `clang-18 --target=aarch64-aros` (or
`clang --target=aarch64-aros`):

```bash
docker run --rm -it -v <dir-with-your-sources>:/work midwan/aros-compiler:aarch64-aros
SDK=/opt/aros-build/bin/raspi-aarch64/AROS/Developer
clang-18 --target=aarch64-aros --sysroot="$SDK" \
  -fno-pic -fno-pie -mcmodel=large -D__AROS__ -O2 \
  -I./include -I"$SDK/include" \
  -idirafter "$SDK/include/aros/posixc" \
  -idirafter "$SDK/include/aros/stdc" -c source.c -o source.o
```

Link the generated objects through `collect-aros`, passing the SDK startup
objects and the AROS libraries required by the project. `clang` is an alias for
`clang-18`. Keep project include directories before `-I"$SDK/include"` when
compiling with Clang. `collect-aros`, `lha`, `make`, `gawk`, and `file` are on
`PATH`.

## Runtime requirements

Every image installs `ca-certificates`, `make`, `gawk`, and `file`. Only `aarch64-aros` installs Ubuntu 24.04's `clang-18` and exposes it as `clang`; i386 and x86_64 retain their GCC toolchains.

## Building locally

```bash
docker build -t midwan/aros-compiler:i386-aros --build-arg aros_target=i386-aros .
docker build -t midwan/aros-compiler:x86_64-aros --build-arg aros_target=x86_64-aros .
docker build -t midwan/aros-compiler:aarch64-aros --build-arg aros_target=aarch64-aros .
```

The build:

1. Clones the AROS source tree (deadwood2 fork for i386/x86_64, aros-development-team fork for aarch64) and the AROS-Contrib repo as `AROS/contrib/`.
2. Builds LHa for UNIX 1.14i-ac from source.
3. Compiles the AROS GCC/binutils cross-toolchain (`make crosstools`).
4. Builds the AROS SDK (`make sdk` for ABIv0; full AROS for ABIv11), including the C `collect-aros` linker needed by aarch64.
5. Installs the xadmaster.library headers via `make xadmaster-includes`.
6. For the aarch64 runtime image only, installs stock Ubuntu 24.04 `clang-18` and exposes it as `clang`.

Expect ~30-60 minutes per variant on a typical CI runner; longer under qemu emulation (e.g. amd64 build on Apple Silicon).

## CI/CD

GitHub Actions builds and pushes all three image tags on every push to `main` and weekly via cron, picking up upstream AROS source changes automatically. The workflow expects `DOCKER_USERNAME` and `DOCKER_PASSWORD` repository secrets.

## Image layout

| Path | Contents |
|---|---|
| `/opt/aros-toolchain/` | i386/x86_64 GCC and target binutils (`i386-aros-gcc`, `i386-aros-ld`, `i386-aros-as`, etc.); already on `PATH` |
| `/opt/aros-toolchain/aarch64-aros/bin/collect-aros` | AROS' C linker for aarch64; on `PATH` before `/opt/aros-toolchain/` |
| `/opt/aros-build/bin/<target>/AROS/{Development,Developer}/include/` | AROS SDK headers (`exec/types.h`, `dos/dos.h`, …) plus the xadmaster headers (`proto/xadmaster.h`, `inline/xadmaster.h`, `clib/xadmaster_protos.h`, `libraries/xadmaster.h`); auto-discovered by GCC and supplied explicitly to Clang |
| `/opt/aros-build/bin/<target>/AROS/{Development,Developer}/lib/` | AROS link libraries (`libamiga.a`, `libautoinit.a`, etc.) used by the GCC driver or `collect-aros` |
| `/usr/bin/clang-18` and `/usr/local/bin/clang` | Ubuntu 24.04 Clang 18 and its `clang` alias; present only in `aarch64-aros` |
| `/opt/lha-bin/bin/lha` | LHa for UNIX 1.14i-ac binary; on `PATH` |

The toolchain include paths are baked into the cross-GCC spec, so `i386-aros-gcc foo.c -o foo` with no extra flags finds AROS headers (and the bundled xadmaster ones) and resolves standard AROS symbols. For aarch64, pass `--target=aarch64-aros` to Clang, place the SDK include directory after project include directories, and link with `collect-aros`.

## Build args

| Arg | Default | Notes |
|---|---|---|
| `aros_target` | `i386-aros` | `i386-aros` (ABIv0), `x86_64-aros` (ABIv11), or `aarch64-aros` (ABIv11 ARM64) |
| `aros_repo` | *(per-target upstream)* | AROS source repo override. Empty selects the target's default (`deadwood2/AROS` for i386/x86_64, `aros-development-team/AROS` for aarch64); set it to build from a fork or pinned mirror |
| `aros_contrib_repo` | `https://github.com/aros-development-team/contrib.git` | AROS-Contrib (xadmaster lives here) |
| `lha_repo` | `https://github.com/jca02266/lha.git` | LHa for UNIX source repo |
| `lha_ref` | `release-20211125` | LHa for UNIX tag/branch (pinned for reproducibility) |
| `ubuntu_release` | `24.04` | Ubuntu base image tag |

## License

GPL-3.0. The Dockerfile and CI configuration are original; the AROS, AROS-Contrib, and LHa for UNIX sources cloned at build time are licensed by their respective upstreams.
