ARG STREAMING_IMAGE
FROM ${STREAMING_IMAGE}
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg python3-venv util-linux \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/preview-tools \
    && /opt/preview-tools/bin/pip install --no-cache-dir 'oci>=2.140,<3'
COPY previews /app/previews
USER node
ENV PREVIEW_STATE_DIR=/state
CMD ["node", "previews/api.mjs"]
