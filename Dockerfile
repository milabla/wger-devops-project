FROM ubuntu:latest
LABEL authors="milab"

ENTRYPOINT ["top", "-b"]
# syntax=docker/dockerfile:1

FROM node:22-slim AS frontend-builder

WORKDIR /app

# Install JS deps first (better layer caching - only re-runs if package.json changes)
COPY package.json package-lock.json* ./
RUN npm install

# Now bring in the scss sources and compile them
COPY wger/core/static/scss ./wger/core/static/scss
RUN npm run build:css:sass


# Stage 2: Backend build (install Python deps, collectstatic)
FROM python:3.13-slim AS backend-builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# System packages needed to build/run psycopg, Pillow, etc.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
        libjpeg-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Official way to get the uv binary into the image (no curl needed)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Install third-party dependencies first (cached separately from app code).
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

# Now copy the rest of the application code
COPY . .

# Install the local project itself now that its source files are present.
RUN uv sync --frozen --no-dev

# Copy node_modules FIRST so collectstatic can pick up JS/CSS vendor files
COPY --from=frontend-builder /app/node_modules ./node_modules

# Copy compiled CSS from Stage 1
COPY --from=frontend-builder /app/wger/core/static/bootstrap-compiled.css \
     ./wger/core/static/bootstrap-compiled.css

ENV DJANGO_DEBUG=False \
    SECRET_KEY=build-time-placeholder-key \
    DJANGO_DB_DATABASE=/tmp/build.sqlite \
    DJANGO_STATIC_ROOT=/app/static \
    DJANGO_MEDIA_ROOT=/app/media

# collectstatic runs AFTER node_modules are in place
RUN uv run python manage.py collectstatic --noinput --skip-checks


# Stage 3: Runtime (small image, only what's needed to run)
FROM python:3.13-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH" \
    DJANGO_STATIC_ROOT=/app/static \
    DJANGO_MEDIA_ROOT=/app/media

# Runtime system libs only (no compilers/headers needed here)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 \
        libjpeg62-turbo \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -u 1000 wger

WORKDIR /app

COPY --from=backend-builder /app /app
COPY docker/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh && chown -R wger:wger /app

USER wger

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
