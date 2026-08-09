# simple-flask-helloworld

Small Flask service for Q5. Returns Hello World plus the build identifier,
has separate liveness and readiness endpoints, runs under Docker Compose and
on a local kind cluster.

## Endpoints

| Path | Purpose |
|---|---|
| `GET /` | `Hello, World!` plus the build identifier |
| `GET /healthz` | liveness — is the server still answering |
| `GET /readyz` | readiness — should this pod get traffic |

```
$ curl -s localhost:8080/
{"build_time":"2026-08-09T00:00:00Z","message":"Hello, World!","version":"abc1234"}
```

## Quickstart

```bash
make up      # docker compose, http://localhost:8080
make smoke   # assert the endpoints and the build identifier
make down

make kind    # create cluster, build, load image, deploy, wait for rollout
make smoke
make kind-down
```

Tests:

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
make test lint
```

## How the build identifier works

The version is not in the source. It is passed at build time and read from the
environment at runtime:

```
docker build --build-arg GIT_SHA=$(git rev-parse --short HEAD) ...
   -> ENV APP_VERSION -> GET / reports it
   -> LABEL org.opencontainers.image.revision (readable without running it)
```

So the same source produces images that identify themselves, and the smoke
test can assert the running container came from the commit under test rather
than from a stale image. That check is the one worth having:

```
EXPECT_VERSION=abc1234 ./scripts/smoke.sh
   version matches the commit under test: abc1234
```

## Why two health endpoints

`/healthz` is liveness and deliberately checks nothing external. If it checked
a dependency, an outage in that dependency would fail the probe on every pod,
restart all of them, and turn a partial outage into a total one.

`/readyz` is readiness and is where a dependency check belongs. It returns 503
before startup finishes and again on SIGTERM, so the pod leaves the Service
endpoints before it stops serving. Liveness stays up during that window so the
kubelet does not restart the pod mid-drain.

## CI

`test` job: ruff, pytest, `pip-audit` on the dependencies.
`e2e` job: build, Trivy scan on the image, kind cluster, load, deploy, smoke.

The dependency scan runs before the build because there is no image to scan
yet; the image scan runs after, because base image CVEs only exist once the
image exists.

## Layout

```
app/main.py            the service
tests/test_routes.py   unit tests
Dockerfile             multi-stage, non-root, gunicorn
compose.yaml           local run
k8s/manifests.yaml     Namespace, Deployment, Service
scripts/smoke.sh       endpoint + version assertions
Makefile               up / kind / smoke / test
```

See `TRADEOFFS.md` for what was left out and why.
