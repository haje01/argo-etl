# 프로젝트 이름
PROJECT=${PROJECT?"Need to set PROJECT"}
# 대상 S3 버킷 ARN
S3_BUCKET=${S3_BUCKET?"Need to set S3_BUCKET"}
# 대상 S3 버킷 ARN
S3_BUCKET_ARN=$(echo "arn::aws::s3:::$S3_BUCKET")
echo "Target Bucket ARN: $S3_BUCKET_ARN"
# 대상 S3 접두사
S3_PREFIX=${S3_PREFIX?"Need to set S3_PREFIX"}
# SNS 토픽 이름 
SNS_TOPIC="$PROJECT-s3-noti"
# 토픽 정책 ID
POLICY_ID="$PROJECT-s3-noti-policy"
# IAM 유저 이름 
IAM_USER="$PROJECT-noti-bot"
# IAM 유저 정책 이름
USER_POLICY="$PROJECT-noti-bot-policy"

# SNS 토픽 제거
ret=$(aws sns list-topics --query "Topics[?contains(TopicArn, \`$SNS_TOPIC\`)].TopicArn" --output text)
echo $ret
if [ -n "$ret" ]; then
    TOPIC_ARN=$ret
    echo "Delete SNS topic : $SNS_TOPIC"
    aws sns delete-topic --topic-arn $TOPIC_ARN
else
    echo "Warning: SNS topic '$SNS_TOPIC' not exists."
fi

# 버킷 알림 제거
echo "Unset bucket notification."
aws s3api put-bucket-notification-configuration --bucket $S3_BUCKET --notification-configuration '{}'

# 알림 전용 IAM 유저 제거
ret=$(aws iam get-user --user-name $IAM_USER 2>&1)
if [ $? -ne 0 ]; then 
    echo "Warning: IAM user '$IAM_USER' not exists."
else
    # IAM 유저 Access Key 제거
    for akey in $(aws iam list-access-keys --user-name $IAM_USER --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
        echo "Delete access key '$akey' from IAM user '$IAM_USER'"
      aws iam delete-access-key --user-name $IAM_USER --access-key-id $akey
    done 
    # IAM 유저 정책  제거
    for policy in $(aws iam list-user-policies --user-name $IAM_USER --query 'PolicyNames' --output text); do
        echo "Delete IAM policy '$policy' from IAM user '$IAM_USER'"
      aws iam delete-user-policy --user-name $IAM_USER --policy-name $policy 
    done 
    echo "Delete IAM user '$IAM_USER'."
    aws iam delete-user --user-name $IAM_USER
fi 

# Helm 차트 변수 파일 제거 
rm -f setup/values.yaml