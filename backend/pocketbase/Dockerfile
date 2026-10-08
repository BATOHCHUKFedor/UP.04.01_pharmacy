# Render settings: Root Directory = backend/pocketbase; Dockerfile Path = Dockerfile.
# Build context must be this directory, not the root of the Flutter repository.
FROM alpine:latest

ARG PB_VERSION=0.40.5
RUN apk add --no-cache ca-certificates unzip \
    && wget -q "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip" -O /tmp/pocketbase.zip \
    && mkdir -p /pb \
    && unzip -q /tmp/pocketbase.zip pocketbase -d /pb \
    && rm /tmp/pocketbase.zip \
    && chmod +x /pb/pocketbase

WORKDIR /pb
COPY pb_hooks/ /pb/pb_hooks/
COPY pb_migrations/ /pb/pb_migrations/

# Mount a Render persistent disk at /pb/pb_data to retain the SQLite database.
# Without a disk, Render Free can reset data, accounts, and sessions.
ENV PHARMACY_ALLOWED_ORIGINS=https://batohchukfedor.github.io
EXPOSE 10000

# Shell expansion is needed for Render's dynamically supplied PORT.
CMD ["/bin/sh", "-c", "exec /pb/pocketbase serve --http=\"0.0.0.0:${PORT:-10000}\" --dir=/pb/pb_data --hooksDir=/pb/pb_hooks --migrationsDir=/pb/pb_migrations --origins=\"${PHARMACY_ALLOWED_ORIGINS}\""]
