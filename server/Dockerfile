# syntax=docker/dockerfile:1.7
# CoD4x 1.8 dedicated server (32-bit). Retail game data (main/, zone/) comes from
# the cod4-game volume (filled by the steamcmd service); the CoD4x package
# (binary, xbase/jcod4x iwds, cod4x_patchv2.ff, steam libs) is baked in here.

FROM debian:bookworm-slim AS fetch
RUN apt-get update && apt-get install -y --no-install-recommends unzip && rm -rf /var/lib/apt/lists/*
# Official linux server package from https://cod4x.ovh/t/releases/24 (v21.2)
ADD --checksum=sha256:feae346d6b4a2cc9e861e170e9072a2b72ae1afa9c3be6771515ad6a4d732451 \
	https://cod4x.ovh/uploads/short-url/59kvOM9hBabZjPJRlLX029BcskI.zip /tmp/cod4x.zip
RUN unzip -q /tmp/cod4x.zip -d /tmp/x && mv /tmp/x/cod4x_server-linux_21.2/cod4x-linux-server /opt/cod4x

FROM debian:bookworm-slim
RUN dpkg --add-architecture i386 \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends libc6:i386 libstdc++6:i386 libgcc-s1:i386 ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

COPY --from=fetch /opt/cod4x /opt/cod4x
COPY entrypoint.sh /opt/cod4x/entrypoint.sh
RUN chmod 755 /opt/cod4x/cod4x18_dedrun /opt/cod4x/entrypoint.sh

# Runs as root inside the container: the game volume is written by the
# steamcmd image (root-owned) and CoD4x files get merged into it.
ENV LD_LIBRARY_PATH=/opt/cod4x
WORKDIR /opt/cod4x
ENTRYPOINT ["/opt/cod4x/entrypoint.sh"]
