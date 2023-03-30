import os
import sys 
import csv 
import json

from minio import Minio

# MinIO 접속 정보
MINIO_ENDPOINT = "minio:9000"
MINIO_USER = os.environ['MINIO_USER']
MINIO_PASSWD = os.environ['MINIO_PASSWD']

# MinIO 오브젝트 정보
BUCKET = sys.argv[1]
KEY = sys.argv[2]
IN_FILE = '/tmp/{os.path.basename(KEY)}'

OUT_FILE = '/tmp/output.json'
NAMES = ['no', 'name', 'score']

# MinIO 에서 입력 오브젝트 내려받기
client = Minio(MINIO_ENDPOINT, access_key=MINIO_USER, secret_key=MINIO_PASSWD, secure=False)
client.fget_object(BUCKET, KEY, IN_FILE)

# CSV 를 읽어 JSON 으로 변환
with open(IN_FILE, 'r') as csv_file:
  reader = csv.reader(csv_file)
  with open(OUT_FILE, 'w') as json_file:
    for cnt, row in enumerate(reader):
      data = dict(zip(NAMES, row))
      json_file.write(json.dumps(data))
      
print(f'Processed {cnt + 1} lines.')