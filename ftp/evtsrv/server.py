import os 
import sys
import json
import time
import logging
from ftplib import FTP
from concurrent import futures

import yaml
import grpc
import generic_pb2
import generic_pb2_grpc

LOG_FMT = '%(asctime)s %(levelname)s : %(message)s'
DT_FMT = '%Y-%m-%d %H:%M:%S'

# 로그 초기화
logging.basicConfig(format=LOG_FMT, datefmt=DT_FMT)
log = logging.getLogger()
log.setLevel(logging.INFO)

# FTP 접속 정보
FTP_USER = os.getenv('FTP_USER')
assert FTP_USER is not None
FTP_PASSWD = os.getenv('FTP_PASSWD')
assert FTP_PASSWD is not None


def _append_file(files, line, szfield, dtfields):
    fields = line.split()
    if len(fields) >= 9:
        fname = fields[-1]
        sz = fields[szfield]
        dt = ' '.join([fields[i] for i in dtfields])
        dt = f'{fields[-4]} {fields[-3]} {fields[-2]}'
        info = dict(sz=sz, dt=dt)
        files[fname] = info


def init_ftp(cfg):
    """FTP 연결."""
    host = cfg.get('host')
    sdir = cfg.get('dir')
    pasv = cfg.get('passive')

    log.info(f"FTP Connect: {host}")
    ftp = FTP(host)
    if pasv:
        log.info("Use passive mode.")
        ftp.set_pasv(True)
    ftp.login(user=FTP_USER, passwd=FTP_PASSWD)
    ftp.cwd(sdir)
    return ftp 


class Eventing(generic_pb2_grpc.EventingServicer):
    """
    - 처음 StartEventSource 가 불리워질 때 이전 파일 기록 초기화
    - 이후로 새로 생성된 파일 정보는 'new' 변경된 파일 정보는 'mod' 로 보냄
    - 재시작 등의 이유로 StartEventSource 가 다시 불리워지면 그 사이에 변경은 놓칠 수 있음
    """
    def StartEventSource(self, request, context):
        # 설정파일 읽기
        scfg = request.config.decode('utf8')
        log.info(f"StartEventSource: {scfg}")
        cfg = yaml.safe_load(scfg)
        ftp = init_ftp(cfg)
        szfields = cfg.get('szfield')
        dtfields = cfg.get('dtfields')

        prev_files = {} 
        # 초기 파일 정보 수집
        ftp.retrlines('LIST -R', lambda line: _append_file(prev_files, line, szfields, dtfields))
        pcnt = len(prev_files)
        if pcnt > 0:
            log.warning("Ignore {pcnt} previously existing files :")
            for fname in prev_files.keys():
                log.warning(f"  {fname}")
                                                           
        # FTP 파일 변경을 모니터링
        while True:
            # 10 초에 한 번씩 바뀐 파일 검사 
            time.sleep(10)

            cur_files = {}
            try:
                # 현재 파일 정보 수집
                ftp.retrlines('LIST -R', lambda line: _append_file(cur_files, line, szfields, dtfields))
            except Exception as e:
                se = str(e)
                if 'Timeout' in se:
                    log.warning("FTP timeout. Reconnect.")
                    ftp = init_ftp(cfg)
                    continue
                else:
                    log.error(se)
                    raise e
                
            # 새로운 또는 갱신된 파일 정보 전송 
            for fname, info in cur_files.items():
                event = None
                if fname not in prev_files:
                    event = 'new'
                    log.info(f"New file: {fname}, Info: {info}")
                    info = dict(name=fname, sz=info['sz'], dt=info['dt'])
                else:
                    pinfo = prev_files[fname]
                    if info['sz'] != pinfo['sz'] or info['dt'] != pinfo['dt']:
                        event = 'mod'
                        info = dict(name=fname, sz=info['sz'], dt=info['dt'])
                        log.info(f"Modified file: {fname}, Info: {info}")
                        payload = json.dumps(info).encode()
                
                # 생성 / 변경된 파일이 있으면 알림
                if event is not None:
                    payload = json.dumps(info).encode()
                    yield generic_pb2.Event(name=event, payload=payload)
                    prev_files[fname] = info


def serve():
    port = '50051'
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=1))
    generic_pb2_grpc.add_EventingServicer_to_server(Eventing(), server)
    server.add_insecure_port('0.0.0.0:' + port)
    server.start()
    log.info("Server started, listening on " + port)
    server.wait_for_termination()


if __name__ == '__main__':
    time.sleep(10)
    serve()
