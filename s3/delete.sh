# 프로젝트 이름
PROJECT=${PROJECT?"Need to set PROJECT"}
# 대상 S3 버킷 ARN
S3_BUCKET=${S3_BUCKET?"Need to set S3_BUCKET"}
# 대상 S3 버킷 ARN
S3_BUCKET_ARN=$(echo "arn::aws::s3:::$S3_BUCKET")
echo "Target Bucket ARN: $S3_BUCKET_ARN"
# SNS 토픽 이름 
SNS_TOPIC="$PROJECT-s3-noti"

# SNS 토픽 제거
ret=$(aws sns list-topics --query "Topics[?contains(TopicArn, \`$SNS_TOPIC\`)].TopicArn" --output text)
if [ -n "$ret" ]; then
    TOPIC_ARN=$ret
    echo "Delete SNS topic '$SNS_TOPIC'"
    aws sns delete-topic --topic-arn $TOPIC_ARN
else
    echo "Warning: SNS topic '$SNS_TOPIC' not exists."
fi

# 버킷 알림 제거
echo "Unset bucket notification."
aws s3api put-bucket-notification-configuration --bucket $S3_BUCKET --notification-configuration '{}'

# Helm 차트 변수 파일 제거 
rm -f vals/*.yaml

# 커스텀 리소스 제거 
kubectl delete eventsource s3 --ignore-not-found