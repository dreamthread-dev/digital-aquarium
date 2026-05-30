FROM python:3.12-slim-bookworm

# Pillow などの外部Cライブラリ依存や curl, git などをインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# requirements.txt は devcontainer 起動時にマウントされる想定、またはここでコピー
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 8000
