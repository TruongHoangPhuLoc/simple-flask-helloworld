# Build stage. Keeps pip and the wheel cache out of the runtime image.
FROM python:3.12-slim AS build
WORKDIR /src
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim

# Passed in by the build. Defaults keep a local `docker build` working.
ARG GIT_SHA=dev
ARG BUILD_TIME=unknown

ENV APP_VERSION=${GIT_SHA} \
    APP_BUILD_TIME=${BUILD_TIME} \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Same identifier on the image itself, so `docker inspect` can answer
# "what commit is this" without running it.
LABEL org.opencontainers.image.revision=${GIT_SHA}

COPY --from=build /install /usr/local
WORKDIR /app
COPY app ./app

# Non-root. Numeric UID so the k8s runAsNonRoot check can verify it.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
USER 10001

EXPOSE 8080

# Not the Flask dev server. It is single-threaded and says itself it is not
# for production.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", \
     "--worker-class", "gthread", "--threads", "4", \
     "--access-logfile", "-", "app.main:app"]
