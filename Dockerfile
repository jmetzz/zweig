FROM debian:stable-slim

# Install required tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    delta \
    curl \
    ca-certificates \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Add non-root user
RUN useradd -m -d /home/zweig zweig

# Copy source into container
COPY . /app
RUN chown -R zweig:zweig /app

# Expose the CLI by linking bin/zg into PATH
RUN ln -s /app/bin/zg /usr/local/bin/zg

# Runtime env
ENV PATH="/usr/local/bin:${PATH}"
ENV ZWEIG_ROOT="/app"

USER zweig

# Working directory (bind mount test repo here via make docker-run)
WORKDIR /app

CMD ["bash"]