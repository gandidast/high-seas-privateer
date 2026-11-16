FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV GODOT_VERSION="4.7.2-stable"
ENV PORT=7860
ENV HOME=/tmp

# Install dependencies required by Godot 4 Headless + nginx WebSocket/HTTP health proxy
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    libfontconfig1 \
    libfreetype6 \
    nginx \
    && rm -rf /var/lib/apt/lists/*

# Download and install Godot 4 Linux x86_64 binary
RUN curl -fSL --retry 3 "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -o /tmp/godot.zip \
    || curl -fSL --retry 3 "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -o /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /usr/local/bin/ \
    && mv "/usr/local/bin/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -f /tmp/godot.zip

WORKDIR /app
COPY . /app

# Pre-generate Godot global script class cache and ensure UID 1000 (Hugging Face) compatibility
RUN sed -i 's/\r$//' /app/deploy/docker-entrypoint.sh \
    && chmod +x /app/deploy/docker-entrypoint.sh \
    && godot --headless --path /app --import || true \
    && chmod -R a+rwX /app

EXPOSE 7860

# Runs nginx on $PORT (7860 on HF Spaces, $PORT on Render/Koyeb) proxying wss:// to Godot --server
CMD ["/app/deploy/docker-entrypoint.sh"]
