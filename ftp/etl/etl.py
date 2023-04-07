import os
import sys
import csv
import json

import boto3
import pandas as pd


# SNS Message 에서 FTP 파일 정보 추출
SNSMSG = sys.argv[1]
print(SNSMSG)
msg = json.loads(SNSMSG)['Message']
frec = json.loads(msg)['Records'][0]
BUCKET = frec['s3']['bucket']['name']
IN_KEY = frec['s3']['object']['key']
DN_FILE = f'/tmp/{os.path.basename(IN_KEY)}'
print(f"Download s3:://{BUCKET}/{IN_KEY} into {DN_FILE}")

OUT_KEY = IN_KEY.replace('input/', 'output/').replace('.csv', '.parquet')
OUT_FILE = '/tmp/output.parquet'
NAMES = ['no', 'name', 'score']

# S3 에서 입력 오브젝트 내려받기
client = boto3.client('s3', region_name='ap-northeast-2')
client.download_file(BUCKET, IN_KEY, DN_FILE)

# Pandas 를 통해 CSV 를 읽고, Parquet 로 저장
df = pd.read_csv(DN_FILE, names=NAMES)
df.to_parquet(OUT_FILE)

# S3 에 결과 업로드
client.upload_file(OUT_FILE, BUCKET, OUT_KEY)

print(f'Processed {len(df)} lines.')