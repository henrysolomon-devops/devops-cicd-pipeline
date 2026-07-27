# v1: Flask app + Docker + HTML dashboard

**Concept demonstrated:** Containerization

## Why Docker?

Running an app directly with Python works fine on one machine, but it depends on that machine already having the right Python version and dependencies installed. Docker solves this by packaging the app together with everything it needs (Python, libraries, code) into a single, portable image. The same image then runs identically on any machine that has Docker installed, whether that's a laptop, a teammate's computer, or a cloud server.

## What's included

A small Flask application with three routes:

- `/` : an HTML dashboard showing the app version, hostname, server time, and a live health status
- `/api/status` : the same information as JSON
- `/health` : a minimal health check endpoint, used later by Kubernetes liveness/readiness probes (v2 onward)

## Running locally (without Docker)

```bash
cd app
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 app.py
```

Visit `http://localhost:5000`.

## Running with Docker

```bash
docker build -f docker/Dockerfile -t devops-cicd-pipeline:v1.0.0 .
docker run -d -p 5000:5000 --name devops-app devops-cicd-pipeline:v1.0.0
```

Visit `http://localhost:5000`.

Stop and remove the container when done:

```bash
docker stop devops-app
docker rm devops-app
```

## Testing

Both the local Python run and the Docker run were verified to behave identically. All three routes (`/`, `/api/status`, `/health`) return the same data, which confirms that containerizing the app didn't change its behavior, it only changed how the app gets packaged and run.
