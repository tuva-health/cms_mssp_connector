FROM ghcr.io/astral-sh/uv:0.10.9@sha256:10902f58a1606787602f303954cea099626a4adb02acbac4c69920fe9d278f82 AS uv
FROM python:3.10.21-slim-bookworm@sha256:7ed92b32353e8d8bd865b5ba811e0315d3999c3b57b1c2df2b504a359d4a1707 AS build

ARG SOURCE_COMMIT
ARG RELEASE_ID

ENV DBT_PROFILES_DIR=/app/config \
    DBT_SEND_ANONYMOUS_USAGE_STATS=false \
    PATH=/app/.venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app
COPY --from=uv /uv /uvx /bin/
RUN printf '%s\n' \
      'deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/20260814T000000Z bookworm main' \
      'deb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/20260814T000000Z bookworm-security main' \
      > /etc/apt/sources.list.d/snapshot.list \
    && rm -f /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends git=1:2.39.5-0+deb12u3 \
    && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY dbt_project.yml packages.yml package-lock.yml ./
RUN dbt deps

COPY . .
RUN SNOWFLAKE_ACCOUNT=build-verification \
    SNOWFLAKE_PRIVATE_KEY=build-verification \
    SNOWFLAKE_PRIVATE_KEY_PASSPHRASE=build-verification \
    SNOWFLAKE_QUERY_TAG=build-verification \
    dbt parse --target dev \
    && python scripts/verify_manifest.py \
      --manifest target/manifest.json \
      --package-lock package-lock.yml \
    && SNOWFLAKE_ACCOUNT=build-verification \
      SNOWFLAKE_PRIVATE_KEY=build-verification \
      SNOWFLAKE_PRIVATE_KEY_PASSPHRASE=build-verification \
      SNOWFLAKE_QUERY_TAG=build-verification \
      dbt parse --target prod --target-path target/prod \
    && python scripts/verify_manifest.py \
      --manifest target/prod/manifest.json \
      --package-lock package-lock.yml \
    && python scripts/create_release_metadata.py image \
      --dev-manifest target/manifest.json \
      --prod-manifest target/prod/manifest.json \
      --source-commit "$SOURCE_COMMIT" \
      --release-id "$RELEASE_ID" \
      --output target/release-metadata.json

FROM python:3.10.21-slim-bookworm@sha256:7ed92b32353e8d8bd865b5ba811e0315d3999c3b57b1c2df2b504a359d4a1707

ARG SOURCE_COMMIT
ARG RELEASE_ID
LABEL org.opencontainers.image.revision="$SOURCE_COMMIT" \
      org.opencontainers.image.version="$RELEASE_ID"

ENV DBT_PROFILES_DIR=/app/config \
    DBT_LOG_PATH=/tmp/dbt-logs \
    DBT_SEND_ANONYMOUS_USAGE_STATS=false \
    PATH=/app/.venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
RUN rm -rf /usr/local/lib/python3.10/site-packages/pip \
      /usr/local/lib/python3.10/site-packages/pip-*.dist-info \
      /usr/local/lib/python3.10/ensurepip \
      /usr/local/bin/pip \
      /usr/local/bin/pip3 \
      /usr/local/bin/pip3.10 \
    && useradd --create-home --uid 10001 dbt
COPY --from=build /app/.venv /app/.venv
COPY --from=build /app/dbt_packages /app/dbt_packages
COPY --from=build --chown=dbt:dbt /app/target/manifest.json /app/target/manifest.json
COPY --from=build --chown=dbt:dbt /app/target/prod/manifest.json /app/target/prod/manifest.json
COPY --from=build /app/target/release-metadata.json /app/release-metadata.json
COPY --from=build /app/analyses /app/analyses
COPY --from=build /app/config/profiles.yml /app/config/profiles.yml
COPY --from=build /app/macros /app/macros
COPY --from=build /app/models /app/models
COPY --from=build /app/scripts /app/scripts
COPY --from=build /app/seeds /app/seeds
COPY --from=build /app/snapshots /app/snapshots
COPY --from=build /app/dbt_project.yml /app/

USER dbt
RUN test ! -w /app \
    && test ! -w /app/config \
    && test ! -w /app/models \
    && test ! -w /app/scripts \
    && test -w /app/target \
    && test ! -e /app/config/.user.yml \
    && rm -rf "$DBT_LOG_PATH" /tmp/runtime-smoke-output /tmp/runtime-smoke-target \
    && test ! -e "$DBT_LOG_PATH" \
    && test -x /app/scripts/run_dbt.sh \
    && SNOWFLAKE_ACCOUNT=build-verification \
      SNOWFLAKE_PRIVATE_KEY=build-verification \
      SNOWFLAKE_PRIVATE_KEY_PASSPHRASE=build-verification \
      SNOWFLAKE_QUERY_TAG=build-verification \
      dbt parse --target dev --target-path /tmp/runtime-smoke-target \
      > /tmp/runtime-smoke-output 2>&1 \
    && test -s /tmp/runtime-smoke-output \
    && test -d "$DBT_LOG_PATH" \
    && test -w "$DBT_LOG_PATH" \
    && test ! -e /app/config/.user.yml \
    && cat /tmp/runtime-smoke-output \
    && rm -rf "$DBT_LOG_PATH" /tmp/runtime-smoke-output /tmp/runtime-smoke-target
ENTRYPOINT ["/app/scripts/run_dbt.sh"]
