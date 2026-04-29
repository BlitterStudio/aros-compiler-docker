# aros-compiler-docker

Docker image with the AROS cross-compiler toolchain, used to build software targeting AROS from any Linux x86_64 host (including GitHub Actions runners).

The image is published on Docker Hub: <https://hub.docker.com/r/midwan/aros-compiler>

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

Inside the container, `i386-aros-gcc` (or `x86_64-aros-gcc`) is on `PATH` along with `make`, `gawk`, and `lha`, so AROS-targeted makefiles work directly.

## Building locally

```bash
docker build -t midwan/aros-compiler:i386-aros   --build-arg aros_target=i386-aros .
docker build -t midwan/aros-compiler:x86_64-aros --build-arg aros_target=x86_64-aros .
```

The build clones the AROS source tree and compiles the cross-toolchain from scratch (`make crosstools`). Expect ~30–60 minutes per variant on a typical CI runner.

## CI/CD

GitHub Actions builds and pushes both image tags on every push to `main` and weekly via cron, picking up upstream AROS source changes automatically. The workflow expects `DOCKER_USERNAME` and `DOCKER_PASSWORD` repository secrets.

## Image layout

| Path | Contents |
|---|---|
| `/opt/aros-toolchain/` | Cross binaries (`i386-aros-gcc`, `i386-aros-ld`, `i386-aros-as`, etc.); already on `PATH` |
| `/opt/aros-build/bin/<target>/AROS/Development/include/` | AROS SDK headers (`exec/types.h`, `dos/dos.h`, etc.); auto-discovered by gcc |
| `/opt/aros-build/bin/<target>/AROS/Development/lib/` | AROS link libraries (`libamiga.a`, `libautoinit.a`, etc.) |

Both paths are baked into the cross-gcc spec, so `i386-aros-gcc foo.c -o foo` with no extra flags will find AROS headers and resolve standard AROS symbols.

## License

GPL-3.0. The Dockerfile and CI configuration are original; the AROS sources cloned at build time are licensed by the AROS project (see `LICENSE.GPL`/`LICENSE.LGPL` in the AROS tree).
