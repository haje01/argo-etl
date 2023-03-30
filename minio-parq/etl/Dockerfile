FROM python:3.10-bullseye

RUN pip install --no-cache-dir minio
RUN pip install --no-cache-dir pandas
RUN pip install --no-cache-dir pyarrow

COPY --chown=python:python etl.py .
