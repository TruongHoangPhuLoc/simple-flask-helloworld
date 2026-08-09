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

`GET /` returns JSON rather than plain text. The brief asked for a response
containing `Hello, World!` and a build identifier; JSON makes the identifier
machine-readable so the smoke test can assert it. The literal string is still
in the body.

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
make venv
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

There are 2 scans setup
+ The first is for dependencies checks along the unit test before build phrase.
+ The second is for scanning the image after we build artifact successfully.

## Not opted in

Things I left out on purpose. They are worth doing in a real setup, they just
buy nothing at this size.

### Deployment configuration

In Q4 I argued for topology spread, a PodDisruptionBudget and a tuned HPA.
None of that is here. That is proportionality, not inconsistency -- Q4 is a
critical-path API with a broker behind it, this is a stateless hello-world
with no dependencies.

| Left out | Would add when |
|---|---|
| HPA | there is real traffic and a measured latency/utilisation curve. Autoscaling on an invented target is worse than a fixed replica count |
| PodDisruptionBudget | the service has an availability target that node drains could breach |
| topologySpreadConstraints | more than one node or zone actually exists and an outage matters |
| Ingress / TLS | something outside the cluster needs to reach it. Right now nothing does |
| Kustomize or Helm | more than one environment, or more than one value that varies. Today it is one image tag, and `kubectl set image` is honest about that |

Kept anyway, because they cost nothing and their absence is a real defect:
separate liveness and readiness probes, resource requests, non-root, a
namespace.

No CPU limit, memory limit set -- same reasoning as Q4. CPU limits throttle
and show up as tail latency; memory is incompressible so its limit is a real
bound.

### Build

- **No build cache.** Dependency caching and container layer caching would cut
  CI time. Not worth the configuration for a build this small.
- **No multi-platform builds.** Single architecture only. amd64/arm64 matters
  once the image runs somewhere other than one laptop and one runner.
- **No Tooling Scans** no tooling scans for quality integrated into the solution such as SonarQube before building artifact.

### Delivery

- **No registry.** CI builds and loads the image straight into kind. A real
  pipeline pushes to a registry and deploys by digest.
- **This is a build path, not a delivery path.** No GitOps, no gated review,
  no production compliance gates. The CD side is deliberately unfinished.
- **What I would add next:** on merge to main, deploy to staging automatically
  off the merge event. Run the automated tests against staging after it
  deploys and report the result. That result is what feeds the decision to
  promote, whether that decision is manual or automated.
- **Promotion, not rebuild.** Production should deploy the same artifact that
  passed staging, not build its own. Rebuilding for production means the thing
  you tested is not the thing you shipped, and that is where drift comes from.
- **No path filtering on CI.** Every push runs the whole pipeline, including
  README-only changes. Filtering is a build-time optimisation and this build is
  about three minutes, so there is little to win.
- **No GitHub environment reserved for production.** Production should be its
  own environment with required reviewers, separate from anything staging can
  reach.

### Safety

- **No branching and protection stragegy** No policy defined for branching, version control strategy. It can be extended to who can trigger which and do what eg, CI runs on development branch, protect at main, not allow pushing directly, triggering on merged PR, deploy new version to staging (given main is for stag and separate branch for prod)

- **No automatic rollback.** If a deploy goes bad, nothing reverts it. The only
  thing limiting the blast radius is the rolling update strategy plus the
  readiness probe: a broken revision fails readiness, so it never takes over
  from the working pods and the rollout stalls with the old version still
  serving. That contains the damage, but it does not undo it -- someone still
  has to run `kubectl rollout undo`. A real setup wires that to the failed
  rollout automatically, or to a health signal after it.

### Cost control
- **Infrastucture** is simple, compabible with single docker host or simple cluster kind, no external dependencies, no IaC workflow wired in. In some cases, when cost control needed, a solution to provision the IaC terraform can be wired in before the application workflow and tearing them down after tests passed. 

### Testing

- **No mocked integration tests.** There are no external dependencies, so a
  mock-based layer would be testing the mock. The real integration surfaces
  are the container booting and the manifests applying, and both are covered:
  `pytest` for routes, compose plus smoke for the image, kind plus smoke for
  the manifests. If this grew a database or a queue, that middle layer would
  be worth having.
- **No External Service exposed** the smoke calls to the application through port-forwarding mechanism. No ExternalService(NodePort/LB) setup. For this size of setup, it builds no thing. Worth implementing with proper templating in kustomize or helm, controlling how we expose the service to external use based on the environment.

### Application

- **No structured logging or metrics endpoint.** gunicorn access logs to
  stdout only. A `/metrics` endpoint would be the next thing I added.
- **Image signing and SBOM** (cosign, syft). Right call for a real supply
  chain, not for an exercise this size.
- **Worker count is a guess.** `--workers 2 --threads 4` with no load test
  behind it. Should come from the CPU request and a measured profile.
- **Version is the short SHA.** Fine for traceability. A release would want a
  semantic version alongside it.
- **Graceful shutdown is partly the application's job.** `/readyz` flips to
  503 on SIGTERM so the pod leaves the Service endpoints; gunicorn drains the
  in-flight requests. No `preStop` hook -- for a stateless service with no
  in-flight work beyond the current request, the default 30s grace period is
  enough.


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
