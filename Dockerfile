ARG LLAMA_BUILD=b9438
ARG DEB_TAG=trixie-slim

FROM ghcr.io/ggml-org/llama.cpp:server-rocm-${LLAMA_BUILD} AS built
FROM docker.io/library/debian:${DEB_TAG} AS getter
ARG DEB_PACKAGES="ca-certificates wget unzip"
ARG LEMONADE_RELEASE=b1281
ARG GPU=gfx1151

RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade \
 && DEBIAN_FRONTEND=noninteractive apt-get -y install ${DEB_PACKAGES} --no-install-recommends \
 && mkdir /tmp/llamacpp \
 && cd /tmp/llamacpp \
 && wget -nv https://github.com/lemonade-sdk/llamacpp-rocm/releases/download/${LEMONADE_RELEASE}/llama-${LEMONADE_RELEASE}-ubuntu-rocm-${GPU}-x64.zip \
 && unzip llama-${LEMONADE_RELEASE}-ubuntu-rocm-${GPU}-x64.zip \
 && rm *llama*


FROM docker.io/library/debian:${DEB_TAG} AS target
ARG DEB_TARGET="libatomic1:amd64 libgomp1:amd64 libstdc++6:amd64 libdrm2:amd64 libdrm-amdgpu1:amd64 libelf1:amd64 libnuma1:amd64 libzstd1:amd64"
COPY --from=getter /tmp/llamacpp /opt/llamacpp
COPY --from=built /app /opt/llamacpp
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade \
 && DEBIAN_FRONTEND=noninteractive apt-get -y install ${DEB_TARGET} --no-install-recommends \
 && apt-get clean \
 && mkdir -p /usr/local/bin \
 && rm -rf /var/lib/apt/lists/ \
 && echo '' >> /etc/profile \
 && echo 'export "PATH=$PATH:/opt/llamacpp"' >> /etc/profile \
 && echo 'export "LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/llamacpp"' >> /etc/profile
ENV PATH="$PATH:/opt/llamacpp"
ENV LD_LIBRARY_PATH="/opt/llamacpp"
ENV LLAMA_ARG_HOST=0.0.0.0
ENTRYPOINT [ "/opt/llamacpp/llama-server" ]
