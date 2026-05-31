# llamacpp pour Strix Halo (ROCm/HIP)
# Inclut le patch PR#21099 : cache reuse pour modèles hybrides/récurrents (DeltaNet, Qwen3.6)
# Patch fermé pour raisons de politique (code IA), fix validé — à retirer quand mergé upstream.
# syntax=docker/dockerfile:1.4
ARG DEB_TAG=trixie-slim
FROM rocm/dev-ubuntu-24.04:7.2.4-complete AS builder

ARG AMDGPU_TARGETS=gfx1151
ARG LLAMA_CPP_REF=master

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git cmake ninja-build curl libcurl4-openssl-dev ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp.git -b ${LLAMA_CPP_REF} . \
 && git log --oneline -1

COPY 21099-recurrent-cache.patch .
RUN git apply 21099-recurrent-cache.patch

RUN cmake -B build -G Ninja \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS="${AMDGPU_TARGETS}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_CURL=ON \
 && cmake --build build --target llama-server -j"$(nproc)" \
 && mkdir -p /opt/llamacpp/bin /opt/llamacpp/lib \
 && cp build/bin/llama-server /opt/llamacpp/bin/ \
 && cp -P build/bin/*.so* /opt/llamacpp/bin/ \
 && while true; do \
      prev=$(find /opt/llamacpp \( -type f -o -type l \) | wc -l); \
      find /opt/llamacpp/bin /opt/llamacpp/lib -type f \
        | xargs ldd 2>/dev/null \
        | awk '/=> \// {print $3}' \
        | grep '^/opt/rocm' | sort -u \
        | while read -r dep; do \
            cp -n "$(readlink -f "$dep")" /opt/llamacpp/lib/ 2>/dev/null || true; \
            cp -Pn "$dep" /opt/llamacpp/lib/ 2>/dev/null || true; \
          done; \
      cur=$(find /opt/llamacpp \( -type f -o -type l \) | wc -l); \
      [ "$cur" -eq "$prev" ] && break; \
    done

# Runtime : Debian slim + dépendances système des libs ROCm (bundlées dans /opt/llamacpp/lib)
FROM docker.io/library/debian:${DEB_TAG} AS target
ARG DEB_TARGET="libatomic1:amd64 libgomp1:amd64 libstdc++6:amd64 libdrm2:amd64 libdrm-amdgpu1:amd64 libelf1:amd64 libnuma1:amd64 libzstd1:amd64"
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade \
 && DEBIAN_FRONTEND=noninteractive apt-get -y install ${DEB_TARGET} --no-install-recommends \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/
COPY --from=builder /opt/llamacpp /opt/llamacpp
ENV PATH="$PATH:/opt/llamacpp/bin"
ENV LD_LIBRARY_PATH="/opt/llamacpp/bin:/opt/llamacpp/lib"
