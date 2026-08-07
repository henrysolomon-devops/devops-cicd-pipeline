from flask import Flask, jsonify, render_template, Response, request, g
import os
import socket
import json
import time
from datetime import datetime, timezone

import redis
import requests
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

# App version - bumped manually at each stage so that when this app is
# deployed to Kubernetes, a rolling update is clearly visible in the response
APP_VERSION = os.environ.get("APP_VERSION", "v1.0.0")

# Which environment this Pod is actually running in - dev, staging, or
# production. This comes from the Helm values file for each namespace,
# so we can tell, just by looking at the dashboard, which environment
# answered the request (useful once GitHub Actions starts deploying to
# all three namespaces automatically, from v4 onward).
APP_ENV = os.environ.get("APP_ENV", "unknown")

# Redis connection details for the weather cache, added in v8. Each
# namespace gets its own lightweight Redis Deployment (no persistent
# volume), so this always points at the in-cluster Service for whichever
# environment this Pod happens to be running in.
REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))

# How long a cached weather reading is considered fresh before the app
# bothers calling Open-Meteo again. Kept short on purpose, since the whole
# point of this cache is to demonstrate real hit/miss behavior on a
# Grafana dashboard, not to minimize API calls for their own sake.
WEATHER_CACHE_TTL_SECONDS = int(os.environ.get("WEATHER_CACHE_TTL_SECONDS", "60"))
WEATHER_CACHE_KEY = "weather:la"

# Fixed coordinates for Los Angeles. Open-Meteo needs plain decimal degrees,
# not a city name, so these are resolved once here rather than looked up
# on every request.
LA_LATITUDE = 34.05
LA_LONGITUDE = -118.24

# The redis-py client doesn't actually open a connection until the first
# command runs, so creating it here is safe even if the Redis Pod isn't
# ready yet when this app starts up. Every place that uses this client
# still wraps the call in a try/except, so a missing or slow Redis never
# takes the whole app down, it just means every request falls back to
# calling Open-Meteo directly.
redis_client = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    decode_responses=True,
    socket_connect_timeout=2,
    socket_timeout=2,
)

# A small lookup table translating Open-Meteo's WMO weather codes into
# plain English. This only covers the common cases; anything not listed
# here just falls back to "Unknown" rather than the app breaking.
WMO_WEATHER_CODES = {
    0: "Clear sky",
    1: "Mainly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Fog",
    48: "Depositing rime fog",
    51: "Light drizzle",
    53: "Moderate drizzle",
    55: "Dense drizzle",
    61: "Slight rain",
    63: "Moderate rain",
    65: "Heavy rain",
    71: "Slight snow fall",
    73: "Moderate snow fall",
    75: "Heavy snow fall",
    80: "Slight rain showers",
    81: "Moderate rain showers",
    82: "Violent rain showers",
    95: "Thunderstorm",
    96: "Thunderstorm with slight hail",
    99: "Thunderstorm with heavy hail",
}

# --- Prometheus metrics, scraped from /metrics by the Prometheus install
# added in v8. These cover three separate things on purpose: general
# request traffic (every route), the Open-Meteo dependency specifically,
# and the Redis cache sitting in front of it, so the Grafana dashboard
# can show all three independently.
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total number of HTTP requests received by the app",
    ["method", "path", "status"],
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Time spent handling each HTTP request, in seconds",
    ["method", "path"],
)
EXTERNAL_API_DURATION = Histogram(
    "external_api_call_duration_seconds",
    "Time spent waiting on a call to an external API",
    ["api"],
)
EXTERNAL_API_ERRORS = Counter(
    "external_api_call_errors_total",
    "Number of failed calls to an external API",
    ["api"],
)
CACHE_HITS = Counter(
    "cache_hits_total",
    "Number of times a cached value was used instead of a fresh lookup",
    ["key"],
)
CACHE_MISSES = Counter(
    "cache_misses_total",
    "Number of times no usable cached value was found",
    ["key"],
)


@app.before_request
def start_timer():
    # Recorded on Flask's per-request context (g), so it's safe even if
    # multiple requests are being handled concurrently.
    g.start_time = time.time()


@app.after_request
def record_request_metrics(response):
    # This runs after every request, including /metrics itself, which is
    # a common and harmless pattern - it just means /metrics shows up as
    # one more path in the request-count graphs.
    duration = time.time() - g.get("start_time", time.time())
    REQUEST_LATENCY.labels(method=request.method, path=request.path).observe(duration)
    REQUEST_COUNT.labels(
        method=request.method, path=request.path, status=response.status_code
    ).inc()
    return response


def get_weather():
    """Return the current Los Angeles conditions, preferring a fresh copy
    from Redis over a live Open-Meteo call whenever one is available. If
    both the cache and the live call fail, this degrades gracefully to an
    "unavailable" state rather than breaking the page that's asking for it.
    """
    cached_value = None
    try:
        cached_value = redis_client.get(WEATHER_CACHE_KEY)
    except Exception:
        # Redis being unreachable is not treated as a hard failure here,
        # it just means we fall through to a live API call below.
        cached_value = None

    if cached_value:
        CACHE_HITS.labels(key="weather").inc()
        return json.loads(cached_value)

    CACHE_MISSES.labels(key="weather").inc()

    start = time.time()
    try:
        response = requests.get(
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": LA_LATITUDE,
                "longitude": LA_LONGITUDE,
                "current_weather": "true",
            },
            timeout=5,
        )
        response.raise_for_status()
        EXTERNAL_API_DURATION.labels(api="open-meteo").observe(time.time() - start)

        current = response.json().get("current_weather", {})
        weather = {
            "temperature_c": current.get("temperature"),
            "condition": WMO_WEATHER_CODES.get(current.get("weathercode"), "Unknown"),
            "source": "live",
        }
    except Exception:
        # Covers network errors, timeouts, and a non-2xx response alike,
        # since none of them should ever crash the page rendering this.
        EXTERNAL_API_DURATION.labels(api="open-meteo").observe(time.time() - start)
        EXTERNAL_API_ERRORS.labels(api="open-meteo").inc()
        return {"temperature_c": None, "condition": "unavailable", "source": "error"}

    try:
        redis_client.setex(WEATHER_CACHE_KEY, WEATHER_CACHE_TTL_SECONDS, json.dumps(weather))
    except Exception:
        # Not being able to write to the cache doesn't matter much here,
        # the next request just ends up calling Open-Meteo again too.
        pass

    return weather


@app.route("/")
def dashboard():
    weather = get_weather()
    return render_template(
        "dashboard.html",
        version=APP_VERSION,
        environment=APP_ENV,
        hostname=socket.gethostname(),
        timestamp=datetime.now(timezone.utc).isoformat(),
        health_status="healthy",
        weather=weather,
    )


@app.route("/api/status")
def api_status():
    weather = get_weather()
    return jsonify({
        "message": "Hello from the DevOps CI/CD demo project!",
        "version": APP_VERSION,
        "environment": APP_ENV,
        "hostname": socket.gethostname(),  # shows which pod/container answered
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "weather": weather,
    })


@app.route("/health")
def health():
    # Used by Kubernetes liveness/readiness probes (from v2 onward).
    # Deliberately left independent of Redis and Open-Meteo, since a slow
    # or unavailable third party has nothing to do with whether this Pod
    # itself is healthy.
    return jsonify({"status": "healthy"}), 200


@app.route("/metrics")
def metrics():
    # Scraped by the Prometheus ServiceMonitor added in v8. Exposed in the
    # standard Prometheus text format, which is what generate_latest()
    # already produces.
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
