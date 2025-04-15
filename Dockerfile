FROM swift:6.1.0-jammy

# --- System setup ---
RUN apt-get update && apt-get install -y \
    libjemalloc-dev \
    curl \
    git \
    libsqlite3-dev \
    libssl-dev \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install Rust + watchexec (portable file watcher for Swift)
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y \
    && export PATH="/root/.cargo/bin:$PATH" \
    && . "/root/.cargo/env" \
    && cargo install watchexec-cli

ENV PATH="/root/.cargo/bin:${PATH}"

# App directory
WORKDIR /app

# Pre-resolve dependencies for caching
COPY ./Package.* ./
RUN swift package resolve

# Copy rest of app
COPY . .

# Expose Vapor's port
EXPOSE 8080

# Default command: watch + rebuid on change
CMD ["watchexec", "-e", "swift,leaf,html,css", "--restart", "--", "swift", "run"]