# aros-compiler-docker

Docker image with the AROS cross-compiler toolchain, used to build software targeting AROS from any Linux x86_64 host (including GitHub Actions runners).

The image is published on Docker Hub: <https://hub.docker.com/r/midwan/aros-compiler>

## What's inside

- AROS cross-compiler (`gcc` + `binutils`) with the AROS SDK (libs + headers) baked into the gcc spec.
- **xadmaster.library headers** from [AROS-Contrib](https://github.com/aros-development-team/contrib) — sources that include `<proto/xadmaster.h>` (e.g. dopus5's `xadopus.module`) cross-compile out of the box.
- **LHa for UNIX 1.14i-ac** ([jca02266/lha](https://github.com/jca02266/lha)) — the full read/write LHA tool, so AROS makefiles that produce `.lha` release archives work without falling back to a separate "packager" image.
- `make`, `gawk`, `file` — the rest of the dopus5 makefile's runtime requirements.

## Tags

| Tag | AROS variant | Branch | Output binary |
|---|---|---|---|
| `i386-aros` | ABIv0 (legacy) | [`deadwood2/AROS` `alt-abiv0`](https://github.com/deadwood2/AROS/tree/alt-abiv0) | `i386-aros-gcc` |
| `x86_64-aros` | ABIv11 (modern) | [`deadwood2/AROS` `master`](https://github.com/deadwood2/AROS) | `x86_64-aros-gcc` |

The `i386-aros` toolchain produces binaries compatible with the AROS distributions most users run today (Icaros Desktop, AROS One). The `x86_64-aros` toolchain targets modern ABIv11 AROS.

## Usage

```bash
docker run --rm -it -v <dir-with-your-sources>:/work midwan/aros-compiler:i386-aros
```

Inside the container, `i386-aros-gcc` (or `x86_64-aros-gcc`) and `lha` are on `PATH` along with `make`, `gawk`, and `file`, so AROS-targeted makefiles work directly — no need for a separate packaging image.

## Building locally

```bash
docker build -t midwan/aros-compiler:i386-aros   --build-arg aros_target=i386-aros .
docker build -t midwan/aros-compiler:x86_64-aros --build-arg aros_target=x86_64-aros .
```

The build:

1. Clones the AROS source tree (deadwood2 fork) and the AROS-Contrib repo as `AROS/contrib/`.
2. Builds LHa for UNIX 1.14i-ac from source.
3. Compiles the cross-toolchain (`make crosstools`).
4. Builds the AROS SDK (`make sdk` for ABIv0; full AROS for ABIv11).
5. Installs the xadmaster.library headers via `make xadmaster-includes`.

Expect ~30-60 minutes per variant on a typical CI runner; longer under qemu emulation (e.g. amd64 build on Apple Silicon).

## CI/CD

GitHub Actions builds and pushes both image tags on every push to `main` and weekly via cron, picking up upstream AROS source changes automatically. The workflow expects `DOCKER_USERNAME` and `DOCKER_PASSWORD` repository secrets.

## Image layout

| Path | Contents |
|---|---|
| `/opt/aros-toolchain/` | Cross binaries (`i386-aros-gcc`, `i386-aros-ld`, `i386-aros-as`, etc.); already on `PATH` |
| `/opt/aros-build/bin/<target>/AROS/Development/include/` | AROS SDK headers (`exec/types.h`, `dos/dos.h`, …) plus the xadmaster headers (`proto/xadmaster.h`, `inline/xadmaster.h`, `clib/xadmaster_protos.h`, `libraries/xadmaster.h`); auto-discovered by gcc |
| `/opt/aros-build/bin/<target>/AROS/Development/lib/` | AROS link libraries (`libamiga.a`, `libautoinit.a`, etc.) |
| `/opt/lha-bin/bin/lha` | LHa for UNIX 1.14i-ac binary; on `PATH` |

The toolchain include paths are baked into the cross-gcc spec, so `i386-aros-gcc foo.c -o foo` with no extra flags finds AROS headers (and the bundled xadmaster ones) and resolves standard AROS symbols.

## Build args

| Arg | Default | Notes |
|---|---|---|
| `aros_target` | `i386-aros` | `i386-aros` (ABIv0) or `x86_64-aros` (ABIv11) |
| `aros_repo` | `https://github.com/deadwood2/AROS.git` | AROS source repo |
| `aros_contrib_repo` | `https://github.com/aros-development-team/contrib.git` | AROS-Contrib (xadmaster lives here) |
| `lha_repo` | `https://github.com/jca02266/lha.git` | LHa for UNIX source repo |
| `lha_ref` | `release-20211125` | LHa for UNIX tag/branch (pinned for reproducibility) |
| `ubuntu_release` | `24.04` | Ubuntu base image tag |

## License

GPL-3.0. The Dockerfile and CI configuration are original; the AROS, AROS-Contrib, and LHa for UNIX sources cloned at build time are licensed by their respective upstreams.
