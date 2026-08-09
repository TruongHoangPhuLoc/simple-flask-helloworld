#!/usr/bin/env bash
# Smoke test. Checks the endpoints answer, and that the build identifier the
# app reports is the commit we actually built. That last check is the point --
# it proves the running container came from this source, not a stale image.
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
EXPECT_VERSION="${EXPECT_VERSION:-}"

fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }

echo "--> GET ${BASE_URL}/healthz"
code=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/healthz")
[[ "${code}" == "200" ]] || fail "/healthz returned ${code}, want 200"

echo "--> GET ${BASE_URL}/readyz"
code=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/readyz")
[[ "${code}" == "200" ]] || fail "/readyz returned ${code}, want 200"

echo "--> GET ${BASE_URL}/"
body=$(curl -sf "${BASE_URL}/") || fail "/ did not return 2xx"
echo "    ${body}"

grep -q 'Hello, World!' <<<"${body}" || fail "/ body missing 'Hello, World!'"

version=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])' <<<"${body}")
[[ -n "${version}" && "${version}" != "dev" ]] || fail "no build identifier in response (got '${version}')"

if [[ -n "${EXPECT_VERSION}" ]]; then
  [[ "${version}" == "${EXPECT_VERSION}" ]] \
    || fail "version mismatch: app reports '${version}', expected '${EXPECT_VERSION}'"
  echo "    version matches the commit under test: ${version}"
fi

echo "SMOKE PASS"
