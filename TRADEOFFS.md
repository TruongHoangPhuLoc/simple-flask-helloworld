# Trade-offs

Scoped to 2-3 hours. Everything below was a deliberate omission, not an
oversight.

## Manifests are minimal, unlike my Q4 answer

In Q4 I argued for topology spread, a PodDisruptionBudget, an HPA with tuned
behavior, and so on. None of that is here. That is not inconsistency, it is
proportionality — Q4 is a critical-path API with a message broker behind it,
this is a stateless hello-world with no dependencies.

Concretely left out, and what would change my mind:

| Left out | Would add when |
|---|---|
| HPA | there is real traffic and a measured latency/utilisation curve. Autoscaling on an invented target is worse than a fixed replica count |
| PodDisruptionBudget | the service has an availability target that node drains could breach |
| topologySpreadConstraints | more than one node/zone actually exists and an outage matters |
| Ingress / TLS | something outside the cluster needs to reach it. Right now nothing does |
| Kustomize or Helm | more than one environment, or more than one value that varies. Today it is one image tag, and `kubectl set image` is honest about that |

Kept anyway because they cost nothing and their absence is a real defect:
separate liveness and readiness probes, resource requests, non-root, a
namespace.

## No mocked integration tests

There are no external dependencies, so a mock-based integration layer would be
testing the mock. The real integration surfaces are the container booting and
the manifests applying, and those are covered end to end:

```
pytest              routes and status codes           seconds
compose + smoke     the image actually serves         ~20s
kind + smoke        manifests valid, pod goes Ready   ~2min
```

If the service grew a database or a queue, that middle layer would be worth
having.

## Liveness does not check anything

Covered in the README. Worth repeating because it looks like laziness and is
not: a liveness probe that checks dependencies converts a dependency outage
into a cluster-wide restart loop.

## Graceful shutdown is partly the application's job

`/readyz` flips to 503 on SIGTERM so the pod drops out of the Service
endpoints. gunicorn handles draining the in-flight requests. There is no
`preStop` hook — for a stateless request/response service with no in-flight
work to protect beyond the current request, the default 30s grace period and
gunicorn's own handling are enough.

## Not done

- **Image signing and SBOM** (cosign, syft). Right call for a real supply
  chain, not for a 2-hour exercise. Would be the first thing I added.
- **No registry push.** CI builds and `kind load`s the image. A real pipeline
  pushes to a registry and deploys by digest, which is what I argued for in Q3.
- **No structured logging or metrics endpoint.** gunicorn access logs to
  stdout only. A `/metrics` endpoint would be the next addition, before
  anything else on this list.
- **Worker count is a guess.** `--workers 2 --threads 4` with no load test
  behind it. Should be derived from the CPU request and a measured profile.
- **No CPU limit, memory limit set.** Same reasoning as Q4 — CPU limits
  throttle and show up as tail latency; memory is incompressible so its limit
  is a real bound.
- **Version is the short SHA.** Fine for traceability. A release would want a
  semantic version alongside it.

## Response format

`GET /` returns JSON rather than plain text. The brief asked for a response
containing `Hello, World!` and a build identifier; JSON makes the identifier
machine-readable so the smoke test can assert it. The literal string is still
in the body.
