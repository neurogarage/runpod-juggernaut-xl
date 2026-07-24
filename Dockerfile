# ---------------------------------------------------------------------------- #
#                        Build the final image                                 #
# ---------------------------------------------------------------------------- #
FROM python:3.10.14-slim

ARG A1111_RELEASE=v1.9.3

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    ROOT=/stable-diffusion-webui \
    PYTHONUNBUFFERED=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && \
    apt install -y \
    fonts-dejavu-core rsync git jq moreutils aria2 wget libgoogle-perftools-dev libtcmalloc-minimal4 procps libgl1 libglib2.0-0 && \
    apt-get autoremove -y && rm -rf /var/lib/apt/lists/* && apt-get clean -y

# Clone the repository
RUN git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git && \
    cd stable-diffusion-webui && \
    git reset --hard ${A1111_RELEASE}

# Pin torch/torchvision to A1111 v1.9.3's tested CUDA 12.1 build. Plain
# `pip install xformers` now pulls torch 2.13+cu130 (CUDA 13.0), which RunPod
# GPU drivers (max CUDA 12.7) can't initialise -> "NVIDIA driver too old" at
# container start. cu121 runs on every RunPod GPU.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
      torch==2.1.2 torchvision==0.16.2 \
      --index-url https://download.pytorch.org/whl/cu121

# xformers matched to torch 2.1.2 (from PyPI; keeps the already-installed torch)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir xformers==0.0.23.post1

# Install requirements_versions.txt with memory optimization
RUN --mount=type=cache,target=/root/.cache/pip \
    cd stable-diffusion-webui && \
    pip install --no-cache-dir -r requirements_versions.txt

# CLIP's legacy setup.py imports pkg_resources, which setuptools>=81 removed,
# so prepare_environment() dies with "Couldn't install clip / No module named
# pkg_resources". Pin setuptools<81 both in the main env AND via PIP_CONSTRAINT
# so PEP517 build-isolation envs (used to build CLIP) also get the old version.
RUN pip install --no-cache-dir "setuptools<81" && \
    printf 'setuptools<81\n' > /etc/pip-constraints.txt
ENV PIP_CONSTRAINT=/etc/pip-constraints.txt

# Stability-AI/stablediffusion was deleted upstream (GitHub 404), so A1111's
# hardcoded clone fails with "could not read Username / error 128". Point it at
# w-e-w's mirror (same pinned commit cf1d67a6). GIT_TERMINAL_PROMPT=0 makes any
# future missing repo fail fast instead of hanging on a credential prompt.
ENV STABLE_DIFFUSION_REPO=https://github.com/w-e-w/stablediffusion.git \
    GIT_TERMINAL_PROMPT=0

# Prepare environment
RUN cd stable-diffusion-webui && \
    python -c "from launch import prepare_environment; prepare_environment()" --skip-torch-cuda-test

# Only the tiny ESRGAN upscaler is baked into the image. The 7GB SDXL
# checkpoint is NOT baked (it made the image ~15GB and workers couldn't pull
# it) — start.sh downloads it once onto the mounted network volume instead.
RUN mkdir -p /stable-diffusion-webui/models/ESRGAN && \
    echo "Downloading upscaler..." && \
    wget --no-check-certificate -q -O /stable-diffusion-webui/models/ESRGAN/4x_NMKD-Siax_200k.pth https://huggingface.co/gemasai/4x_NMKD-Siax_200k/resolve/main/4x_NMKD-Siax_200k.pth || exit 1 && \
    test -f /stable-diffusion-webui/models/ESRGAN/4x_NMKD-Siax_200k.pth || (echo "ERROR: upscaler not found" && exit 1) && \
    echo "Upscaler downloaded."

# install dependencies
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

COPY test_input.json .

ADD src .

RUN chmod +x /start.sh
CMD /start.sh