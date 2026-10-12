FROM ghcr.io/felddy/foundryvtt:14

ARG BUILD_VERSION
ARG BUILD_ARCH

LABEL \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.type="addon" \
  io.hass.arch="${BUILD_ARCH}"

USER root

# The upstream image assumes /data. HAOS exposes addon_config at /config, so
# keep the upstream installer, launcher and generated options on that path.
RUN sed -i 's|/data|/config|g' \
      /home/node/entrypoint.sh \
      /home/node/launcher.sh \
      /home/node/set_options.js \
      /home/node/backoff.sh \
    && apt-get update \
    && apt-get install -y --no-install-recommends gosu \
    && rm -rf /var/lib/apt/lists/*

COPY run.sh /run.sh
RUN sed -i 's/\r$//' /run.sh && chmod 0755 /run.sh

ENTRYPOINT ["/usr/bin/env", "bash", "/run.sh"]
