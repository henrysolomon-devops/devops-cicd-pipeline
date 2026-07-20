# Start from an official, lightweight Python base image.
# "slim" is a smaller variant of the full Python image — it strips out
# extra tools we don't need, keeping the final image size down.

FROM python:3.12-slim

# Set the working directory inside the container.
# All following commands (COPY, RUN, CMD) happen relative to this path.

WORKDIR /app

# Copy only the requirements file first, not the whole app yet.
# This is a deliberate ordering trick: Docker caches each step (layer).
# If requirements.txt hasn't changed, Docker reuses the cached
# "pip install" layer instead of re-running it on every build,
# even if the app code itself changed. This makes rebuilds much faster.

COPY app/requirements.txt .

# Install dependencies.
# --no-cache-dir keeps pip from storing a local download cache,
# which would otherwise bloat the image with files we'll never use again.

RUN pip install --no-cache-dir -r requirements.txt

# Now copy the rest of the application code.
# Paths are relative to the build context (the repo root), since that's
# what we pass to `docker build` — not relative to this Dockerfile's location.

COPY app/app.py .
COPY app/templates/ templates/

# Document which port the app listens on.
# This is informational only — it does not actually publish the port;
# that happens later with `docker run -p`.

EXPOSE 5000

# Set a default value for the app version. This can be overridden
# at container run time, e.g.: docker run -e APP_VERSION=v1.2.0 ...

ENV APP_VERSION=v1.0.0

# The command that runs when the container starts.

CMD ["python3", "app.py"]
