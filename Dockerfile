FROM python:3.10-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    libgomp1 \
 && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip setuptools wheel packaging \
 && awk '!/^flash-attn==/' requirements.txt > requirements.base.txt \
 && pip install --no-cache-dir -r requirements.base.txt

# Copy application code
COPY . .

EXPOSE 8000

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV MODEL_WARMUP=true
ENV TORCH_DEVICE=cuda
ENV PIP_NO_CACHE_DIR=1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
