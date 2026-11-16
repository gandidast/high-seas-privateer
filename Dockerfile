FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV GODOT_VERSION="4.7.2-stable"
ENV PORT=8080

# Install dependencies required by Godot 4 Headless on Ubuntu 22.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    libfontconfig1 \
    libfreetype6 \
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

EXPOSE 8080

# Render.com and Koyeb inject $PORT automatically; NetworkManager reads OS.get_environment("PORT") (fallback 8080)
CMD ["godot", "--headless", "--path", "/app", "--", "--server"]
