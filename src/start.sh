#!/usr/bin/env bash

echo "Worker Initiated"

# The SDXL checkpoint lives on the network volume (mounted at /runpod-volume)
# instead of being baked into the image, so the image stays small (~4GB) and
# workers pull it quickly. Download the model once if it isn't on the volume;
# every later worker finds it already there and starts fast.
if [ -d /runpod-volume ]; then
  MODEL_DIR=/runpod-volume/models/Stable-diffusion
else
  echo "WARNING: no network volume at /runpod-volume — using local (ephemeral) storage; the model will re-download on every cold start."
  MODEL_DIR=/stable-diffusion-webui/models/Stable-diffusion
fi
MODEL="$MODEL_DIR/JuggernautXL.safetensors"
MODEL_URL="https://huggingface.co/SG161222/RealVisXL_V5.0/resolve/main/RealVisXL_V5.0_fp16.safetensors"

mkdir -p "$MODEL_DIR"
if [ ! -f "$MODEL" ]; then
  echo "Checkpoint not found, downloading RealVisXL V5.0 (~7GB, one-time)..."
  if wget --no-check-certificate -q -O "$MODEL.tmp.$$" "$MODEL_URL"; then
    mv -f "$MODEL.tmp.$$" "$MODEL"
    echo "Checkpoint downloaded to $MODEL"
  else
    echo "ERROR: checkpoint download failed"
    rm -f "$MODEL.tmp.$$"
  fi
else
  echo "Checkpoint already present at $MODEL"
fi

echo "Starting WebUI API"
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"
export PYTHONUNBUFFERED=true
python /stable-diffusion-webui/webui.py \
  --xformers \
  --no-half-vae \
  --skip-python-version-check \
  --skip-torch-cuda-test \
  --skip-install \
  --ckpt "$MODEL" \
  --ckpt-dir "$MODEL_DIR" \
  --opt-sdp-attention \
  --disable-safe-unpickle \
  --port 3000 \
  --api \
  --nowebui \
  --skip-version-check \
  --no-hashing \
  --no-download-sd-model &

echo "Starting RunPod Handler"
python -u /handler.py
