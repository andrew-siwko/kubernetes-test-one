# ==========================================================
# Stage 1: Build & Install dependencies
# ==========================================================
FROM python:3.11-slim AS builder

WORKDIR /app

# Install system-level build tools only if your pip packages require compilation 
# (e.g., packages like cryptography, psutil, or greenlet might need these).
# If your requirements are simple, you can comment this block out to speed up builds.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy only requirements first to leverage Docker's build cache
COPY requirements.txt .

# Install dependencies into a localized directory to copy over later
RUN pip install --no-cache-dir --user -r requirements.txt


# ==========================================================
# Stage 2: Final lightweight runtime environment
# ==========================================================
FROM python:3.11-slim AS runner

WORKDIR /app

# Copy the pre-installed pip packages from the builder stage
COPY --from=builder /root/.local /root/.local
# Copy your application source code
COPY . .

# Ensure the local pip binary path is in the system PATH
ENV PATH=/root/.local/bin:$PATH

# Prevent Python from writing .pyc files to disk and force unbuffered logging 
# (crucial for seeing container logs instantly in 'kubectl logs')
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Expose the port your application listens on (adjust if your app uses a different port)
EXPOSE 8000

# The command to execute your application
CMD ["python", "app.py"]
