# GIT_SHA drives the image tag and the identifier the app reports, so a local
# run behaves the same way CI does.
# --short can return more than 7 chars on a big repo, but CI uses
# ${GITHUB_SHA::7}. Pin the length so a local build and a CI build of the same
# commit produce the same tag and the same reported version.
GIT_SHA    ?= $(shell git rev-parse --short=7 HEAD 2>/dev/null || echo dev)$(shell git diff --quiet 2>/dev/null || echo -dirty)
BUILD_TIME ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
IMAGE      := simple-flask-helloworld:$(GIT_SHA)
KIND_CLUSTER ?= simple-flask-helloworld

export GIT_SHA BUILD_TIME

.PHONY: help test lint build up down kind kind-down deploy smoke clean

help:
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/'

test: ## unit tests
	.venv/bin/python -m pytest -q

lint: ## ruff
	.venv/bin/ruff check .

build: ## build the image
	docker build --build-arg GIT_SHA=$(GIT_SHA) --build-arg BUILD_TIME=$(BUILD_TIME) -t $(IMAGE) .

up: ## run locally with compose
	docker compose up --build -d
	@echo "http://localhost:8080"

down:
	docker compose down

kind: build ## create the cluster, load the image, deploy, wait
	kind get clusters | grep -qx $(KIND_CLUSTER) || kind create cluster --name $(KIND_CLUSTER)
	kind load docker-image $(IMAGE) --name $(KIND_CLUSTER)
	$(MAKE) deploy

deploy:
	kubectl apply -f k8s/manifests.yaml
	# Set the real tag rather than templating the manifest -- one moving part
	# in a repo this size does not need Kustomize.
	kubectl -n hello set image deployment/hello hello=$(IMAGE)
	kubectl -n hello rollout status deployment/hello --timeout=120s

smoke: ## port-forward and assert endpoints + version
	kubectl -n hello port-forward svc/hello 8080:80 & echo $$! > .pf.pid
	sleep 3
	EXPECT_VERSION=$(GIT_SHA) ./scripts/smoke.sh; status=$$?; \
	kill $$(cat .pf.pid) 2>/dev/null; rm -f .pf.pid; exit $$status

kind-down:
	kind delete cluster --name $(KIND_CLUSTER)

clean: down kind-down
	rm -rf .pytest_cache **/__pycache__
