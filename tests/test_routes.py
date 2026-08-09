import pytest

from app.main import _on_sigterm, app, set_ready


@pytest.fixture
def client():
    app.config.update(TESTING=True)
    set_ready(True)
    with app.test_client() as c:
        yield c


def test_root_says_hello(client):
    r = client.get("/")
    assert r.status_code == 200
    assert r.get_json()["message"] == "Hello, World!"


def test_root_reports_a_build_identifier(client):
    # Only checks the value is wired through. CI asserts it equals the commit.
    assert client.get("/").get_json()["version"]


def test_healthz_ok(client):
    assert client.get("/healthz").status_code == 200


def test_readyz_ok_when_ready(client):
    assert client.get("/readyz").status_code == 200


def test_readyz_503_when_not_ready(client):
    set_ready(False)
    assert client.get("/readyz").status_code == 503


def test_sigterm_drops_readiness_but_not_liveness(client):
    # Readiness drops so we leave the endpoints. Liveness stays up so the
    # kubelet does not restart us in the middle of draining.
    _on_sigterm(15, None)
    assert client.get("/readyz").status_code == 503
    assert client.get("/healthz").status_code == 200
