FROM python:3.10-bullseye

RUN pip install pyyaml
RUN pip install grpcio
RUN pip install grpcio-tools

COPY --chown=python:python generic_pb2.py .
COPY --chown=python:python generic_pb2_grpc.py .
COPY --chown=python:python server.py .
