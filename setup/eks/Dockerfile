FROM alpine:3.17

RUN apk add --no-cache curl
RUN apk add --no-cache aws-cli
RUN curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
RUN mv /tmp/eksctl /usr/local/bin

CMD /init.sh; sleep infinity