FROM ubuntu:24.04
# Set architecture explicitly
ARG TARGETARCH=amd64
# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    valgrind \
    g++ \
    libgoogle-perftools-dev \
    google-perftools \
    python3 \
    python3-venv \
    git \
    perl \
    autoconf \
    automake \
    libtool \
    libunwind-dev \
    graphviz \
    libperl-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*
# Manually install pprof from gperftools source (fallback if google-perftools fails)
RUN git clone --branch gperftools-2.10 https://github.com/gperftools/gperftools.git && \
    cd gperftools && \
    ./autogen.sh && \
    ./configure --enable-frame-pointers && \
    make && \
    make install && \
    if [ -n "$(find . -name pprof)" ]; then \
        find . -name pprof -exec cp {} /usr/bin/pprof \; ; \
    else \
        echo "ERROR: pprof binary not found in gperftools build" >&2; \
        exit 1; \
    fi && \
    cd .. && rm -rf gperftools
# Create and activate virtual environment
RUN python3 -m venv /app/venv
ENV PATH="/app/venv/bin:$PATH"
# Install Python packages
RUN pip install --no-cache-dir pandas regex
WORKDIR /app

# ---- Copy Action files -----------------------------------------------------
WORKDIR /app
COPY action.yml entrypoint.sh parse_profile.py ./
RUN chmod +x entrypoint.sh

# ---- Working directory for user code ---------------------------------------
WORKDIR /workspace
ENTRYPOINT ["/app/entrypoint.sh"]