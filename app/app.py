from flask import Flask, jsonify, render_template
import os
import socket
from datetime import datetime, timezone

app = Flask(__name__)

# App version - bumped manually at each stage so that when this app is
# deployed to Kubernetes, a rolling update is clearly visible in the response
APP_VERSION = os.environ.get("APP_VERSION", "v1.0.0")


@app.route("/")
def dashboard():
    return render_template(
        "dashboard.html",
        version=APP_VERSION,
        hostname=socket.gethostname(),
        timestamp=datetime.now(timezone.utc).isoformat(),
        health_status="healthy",
    )


@app.route("/api/status")
def api_status():
    return jsonify({
        "message": "Hello from the DevOps CI/CD demo project!",
        "version": APP_VERSION,
        "hostname": socket.gethostname(),  # shows which pod/container answered
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


@app.route("/health")
def health():
    # Used by Kubernetes liveness/readiness probes (from v2 onward)
    return jsonify({"status": "healthy"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
