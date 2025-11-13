#!/bin/bash
# Build devbox-status binary for Docker image
set -e

cd "$(dirname "$0")"

echo "Building devbox-status..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o devbox-status .

echo "✓ Built devbox-status binary"
ls -lh devbox-status
