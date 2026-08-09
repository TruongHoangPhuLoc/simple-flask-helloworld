import os
import signal

from flask import Flask, jsonify

# Version comes from the image build, not from the source. Same code, different
# build, different identifier. See the Dockerfile ARGs.
VERSION = os.environ.get("APP_VERSION", "dev")
BUILD_TIME = os.environ.get("APP_BUILD_TIME", "unknown")

app = Flask(__name__)

# Readiness state. Starts False, goes True once we are up, goes back to False
# on SIGTERM so we drop out of the Service endpoints before we stop serving.
_ready = False


def set_ready(value: bool) -> None:
    global _ready
    _ready = value


def is_ready() -> bool:
    return _ready


@app.get("/")
def hello():
    return jsonify(
        message="Hello, World!",
        version=VERSION,
        build_time=BUILD_TIME,
    )


# Liveness. Deliberately checks nothing external. If it did, a dependency
# outage would fail this probe on every pod, restart all of them, and turn a
# partial outage into a full one. All this proves is that the server still
# answers, which is what liveness is for.
@app.get("/healthz")
def healthz():
    return jsonify(status="ok"), 200


# Readiness. This is where a dependency check belongs if we ever have one.
# Nothing external here yet, so it only reports the lifecycle state.
@app.get("/readyz")
def readyz():
    if not is_ready():
        return jsonify(status="not ready"), 503
    return jsonify(status="ready"), 200


def _on_sigterm(signum, frame):
    # Stop taking new traffic. gunicorn still drains the in-flight requests.
    set_ready(False)


signal.signal(signal.SIGTERM, _on_sigterm)
set_ready(True)
