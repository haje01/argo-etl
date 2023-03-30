FROM python:3.10-bullseye

RUN pip install --no-cache-dir minio

COPY --chown=python:python etl.py .
