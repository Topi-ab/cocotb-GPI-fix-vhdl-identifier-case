# syntax=docker/dockerfile:1.7
#
# Free simulators and build tools for verifying the cocotb VHDL identifier case fix:
# NVC 1.23.0, GHDL 6.0.0 (LLVM), Icarus Verilog and Verilator (oss-cad-suite 2025-09-07).
#
# The simulators are prebuilt releases, each pinned by digest or SHA-256; the Ubuntu packages come
# from the archive when the image is built. Nothing is compiled here; cocotb is built at run time
# inside the container (see verify/build.sh).

FROM ghdl/ghdl:6.0.0-llvm-ubuntu-24.04@sha256:8b3ec37c3873b2eee9387759e66c50830c15ae5b7b533badaa97ce007a0f8022 AS ghdl

FROM ubuntu:24.04@sha256:c35e29c9450151419d9448b0fd75374fec4fff364a27f176fb458d472dfc9e54 AS oss-cad-suite
ADD --checksum=sha256:75185cedfdd948d0782ebf4d3b68b5cdb953d11aae5c53dea4259dc0a0eed3e5 \
    https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2025-09-07/oss-cad-suite-linux-x64-20250907.tgz \
    /tmp/oss-cad-suite.tgz
RUN mkdir -p /opt && tar -xzf /tmp/oss-cad-suite.tgz -C /opt && rm /tmp/oss-cad-suite.tgz

FROM ubuntu:24.04@sha256:c35e29c9450151419d9448b0fd75374fec4fff364a27f176fb458d472dfc9e54

ADD --checksum=sha256:33d65eafb83d83352716895e44c116002f94d8a198a9486a3cee6df3e4fdfb89 \
    https://github.com/nickg/nvc/releases/download/r1.23.0/nvc_1.23.0-1_amd64_ubuntu-24.04.deb \
    /tmp/nvc.deb

# NVC, the GHDL runtime dependencies (from /opt/ghdl/ubuntu.requirements), and the tools to
# build cocotb and run its tests.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        /tmp/nvc.deb \
        libgnat-13 libllvm18 gcc g++ libc-dev zlib1g-dev \
        python3 python3-venv python3-dev \
        make perl git ca-certificates ccache cmake ninja-build \
 && rm -rf /var/lib/apt/lists/* /tmp/nvc.deb

COPY --from=ghdl /opt/ghdl /opt/ghdl
# The GHDL image has no license text under /opt/ghdl.
ADD --checksum=sha256:aef8b4222b79d0dbf6bf17cfff71c90a6a6bb8917a4162abe417b469ed22da2e \
    https://raw.githubusercontent.com/ghdl/ghdl/v6.0.0/COPYING.md /opt/ghdl/COPYING.md
COPY --from=oss-cad-suite /opt/oss-cad-suite /opt/oss-cad-suite

# The vvp wrapper of oss-cad-suite sets its own dynamic loader and libc, which stops vvp from
# loading cocotb (GLIBC_2.36 not found). The vvp here runs the vvp binary directly. cocotb runs
# Icarus from ICARUS_BIN_DIR, so iverilog is there too.
COPY iverilog vvp /opt/icarus/bin/
COPY versions.sh /usr/local/bin/versions
RUN chmod 755 /opt/icarus/bin/iverilog /opt/icarus/bin/vvp /usr/local/bin/versions

# oss-cad-suite goes last, so that GHDL, NVC and Python are the ones installed above.
ENV ICARUS_BIN_DIR=/opt/icarus/bin \
    PATH=/opt/ghdl/bin:/opt/icarus/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/oss-cad-suite/bin

RUN versions

LABEL org.opencontainers.image.source="https://github.com/Topi-ab/cocotb-GPI-fix-vhdl-identifier-case" \
      org.opencontainers.image.description="NVC, GHDL, Icarus Verilog and Verilator for verifying the cocotb VHDL identifier case fix"
