FROM python:3.10-bullseye

RUN pip install --no-cache-dir boto3
RUN pip install --no-cache-dir pyarrow
RUN pip install --no-cache-dir pandas

COPY --chown=python:python etl.py .