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

# Install xformers separately to reduce memory pressure
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir xformers

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

# Prepare environment
RUN cd stable-diffusion-webui && \
    python -c "from launch import prepare_environment; prepare_environment()" --skip-torch-cuda-test

# Download models directly in the final image (no duplication!)
# Чекпоинт — RealVisXL V5.0 (публичный, БЕЗ gated/токена): фотореалистичный
# нецензурный SDXL. Имя файла оставлено JuggernautXL.safetensors, т.к. на него
# ссылается override_settings в запросах и загрузчик A1111.
RUN mkdir -p /stable-diffusion-webui/models/Stable-diffusion && \
    mkdir -p /stable-diffusion-webui/models/ESRGAN && \
    echo "Downloading models..." && \
    wget --no-check-certificate -q -O /stable-diffusion-webui/models/Stable-diffusion/JuggernautXL.safetensors https://huggingface.co/SG161222/RealVisXL_V5.0/resolve/main/RealVisXL_V5.0_fp16.safetensors || exit 1; \
    wget --no-check-certificate -q -O /stable-diffusion-webui/models/ESRGAN/4x_NMKD-Siax_200k.pth https://huggingface.co/gemasai/4x_NMKD-Siax_200k/resolve/main/4x_NMKD-Siax_200k.pth || exit 1; \
    echo "Verifying downloads..." && \
    test -f /stable-diffusion-webui/models/Stable-diffusion/JuggernautXL.safetensors || (echo "ERROR: checkpoint not found" && exit 1) && \
    test -f /stable-diffusion-webui/models/ESRGAN/4x_NMKD-Siax_200k.pth || (echo "ERROR: 4x_NMKD-Siax_200k.pth not found" && exit 1) && \
    ls -lh /stable-diffusion-webui/models/Stable-diffusion/ && \
    ls -lh /stable-diffusion-webui/models/ESRGAN/ && \
    echo "Download successful!"

# install dependencies
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

COPY test_input.json .

ADD src .

RUN chmod +x /start.sh
CMD /start.sh