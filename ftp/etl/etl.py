import os                                                                                                                
import sys
import json
from ftplib import FTP
import base64
import tempfile
import time

import boto3
import pandas as pd
import yaml

COLUMNS = ['no', 'name', 'score']

# FTP 접속 정보
FTP_HOST = os.getenv('FTP_HOST')
assert FTP_HOST is not None
FTP_USER = os.getenv('FTP_USER')
assert FTP_USER is not None
FTP_PASSWD = os.getenv('FTP_PASSWD')
assert FTP_PASSWD is not None
# 결과 저장할 버킷과 접두사
S3_BUCKET = os.getenv('S3_BUCKET')
assert S3_BUCKET is not None
S3_PREFIX = os.getenv('S3_PREFIX')
assert S3_PREFIX is not None
assert FTP_PASSWD is not None

payload = base64.b64decode(sys.argv[1]).decode()
info = json.loads(payload)
print(f"FTP Notification: {info}")
      
# FTP 파일 정보
path = info.get('name')
sz = info.get('sz')
dt = info.get('dt')

in_file = tempfile.mkstemp()[1]
out_file = '/tmp/output.parquet'
s3_key = S3_PREFIX + path.replace('.csv', '.parquet')

# FTP 에서 소스 파일 내려받기
ftp = FTP(FTP_HOST)
ftp.set_pasv(True)  # 필요에 따라 설정
ftp.login(user=FTP_USER, passwd=FTP_PASSWD)
print(f"Download file '{path}'")
with open(in_file, 'wb') as fp:
    ftp.retrbinary(f'RETR {path}', fp.write)

# Pandas 를 통해 CSV 를 읽고, Parquet 로 저장
df = pd.read_csv(in_file, names=COLUMNS)
df.to_parquet(out_file)

print(f'Processed {len(df)} lines.')

# S3 에 결과 업로드
client = boto3.client('s3', region_name='ap-northeast-2')
client.upload_file(out_file, S3_BUCKET, s3_key)
print(f'Uploaded to S3: {os.path.join(S3_BUCKET, s3_key)}')