FROM python:3.10-bullseye

RUN pip install --no-cache-dir pyyaml
RUN pip install --no-cache-dir grpcio
RUN pip install --no-cache-dir grpcio-tools

COPY --chown=python:python generic_pb2.py .
COPY --chown=python:python generic_pb2_grpc.py .
COPY --chown=python:python server.py .
