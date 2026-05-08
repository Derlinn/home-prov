#!/usr/bin/env bash
set -euo pipefail

# Create the Python venv with the pinned version (python3.14 installed via deadsnakes)
python3.14 -m venv .venv

# Activate venv automatically in interactive shells
echo 'source /workspaces/home-prov/.venv/bin/activate' >> ~/.bashrc

# Install project Python deps if any
if [ -f requirements.txt ]; then
  .venv/bin/pip install -r requirements.txt
elif [ -f requirements-dev.txt ]; then
  .venv/bin/pip install -r requirements-dev.txt
fi

# Set up pre-commit hooks
pre-commit install
