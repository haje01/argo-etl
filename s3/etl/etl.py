import os
import sys
import csv
import json

import boto3
import pandas as pd

# S3 접속 정보
ACCESS_KEY = os.environ['S3_ACCESS_KEY'].strip()
SECRET_KEY = os.environ['S3_SECRET_KEY'].strip()

print(ACCESS_KEY)
print(SECRET_KEY)

# SNS Message 에서 정보 추출
SNSMSG = sys.argv[1]
msg = json.loads(SNSMSG)['Message']
frec = json.loads(msg)['Records'][0]
BUCKET = frec['s3']['bucket']['name']
IN_KEY = frec['s3']['object']['key']
IN_FILE = f'/tmp/{os.path.basename(IN_KEY)}'

OUT_KEY = IN_KEY.replace('input/', 'output/').replace('.csv', '.parquet')
OUT_FILE = '/tmp/output.parquet'
NAMES = ['no', 'name', 'score']

# S3 에서 입력 오브젝트 내려받기
client = boto3.client('s3', aws_access_key_id=ACCESS_KEY, aws_secret_access_key=SECRET_KEY)
client.download_file(BUCKET, IN_KEY, IN_FILE)

# Pandas 를 통해 CSV 를 읽고, Parquet 로 저장
df = pd.read_csv(IN_FILE, names=NAMES)
df.to_parquet(OUT_FILE)

# S3 에 결과 업로드
client.upload_file(OUT_FILE, BUCKET, OUT_KEY)

print(f'Processed {len(df)} lines.')