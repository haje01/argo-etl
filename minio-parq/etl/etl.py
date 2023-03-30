import os
import sys 
from tempfile import _get_candidate_names

from minio import Minio
import pandas as pd

# MinIO 접속 정보
MINIO_ENDPOINT = "minio:9000"
MINIO_USER = os.environ['MINIO_USER']
MINIO_PASSWD = os.environ['MINIO_PASSWD']

# MinIO 오브젝트 정보
bucket = sys.argv[1]
key = sys.argv[2] 
in_file = next(_get_candidate_names())
out_file = '/tmp/output.parquet'
cols = ['no', 'name', 'score']

# MinIO 에서 소스 오브젝트 내려받기
client = Minio(MINIO_ENDPOINT, access_key=MINIO_USER, secret_key=MINIO_PASSWD, secure=False)
client.fget_object(bucket, key, in_file)

# Pandas 를 통해 CSV 를 읽고, Parquet 로 저장
df = pd.read_csv(in_file, names=cols)
df.to_parquet(out_file)

print(f'Processed {len(df)} lines.')