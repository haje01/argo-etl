# 프로젝트 이름
PROJECT=${PROJECT?"Need to set PROJECT"}
# 대상 S3 버킷 
S3_BUCKET=${S3_BUCKET?"Need to set S3_BUCKET"}
# 대상 S3 버킷 ARN
S3_BUCKET_ARN=$(echo "arn:aws:s3:::$S3_BUCKET")
echo "Target Bucket ARN: $S3_BUCKET_ARN"
# 대상 S3 접두사
S3_PREFIX=${S3_PREFIX?"Need to set S3_PREFIX"}
# SNS 토픽 이름 
SNS_TOPIC="$PROJECT-s3-noti"
# 알림 ID
NOTI_ID="$PROJECT-s3-noti"
# 토픽 정책 ID
POLICY_ID="$PROJECT-s3-noti-policy"
# IAM 유저 이름 
IAM_USER="$PROJECT-noti-bot"
# IAM 유저 정책 이름
USER_POLICY="$PROJECT-noti-bot-policy"

# 버킷 존재 여부 확인 
ret=$(aws s3api head-bucket --bucket "$S3_BUCKET" 2>&1)
echo $ret
if [ -n "$ret" ]; then 
    echo "Bucket '$S3_BUCKET' not exists."
    exit 1
fi 

# SNS 토픽 생성
ret=$(aws sns list-topics --query "Topics[?contains(TopicArn, \`$SNS_TOPIC\`)].TopicArn" --output text)
if [ -z "$ret" ]; then
    echo "Create SNS topic : $SNS_TOPIC"
    ret=$(aws sns create-topic --name $SNS_TOPIC)
    TOPIC_ARN=$(echo $ret | jq -r '.TopicArn')
else
    echo "SNS topic '$SNS_TOPIC' already exists."
    TOPIC_ARN="arn:aws:sns:ap-northeast-2:$AWS_ACCOUNT_ID:$SNS_TOPIC"
fi
echo "Topic ARN: $TOPIC_ARN"
# 차트 설치를 위한 value 파일 생성 
echo "# This file should be kept as secret!" > setup/values.yaml
echo "topicArn: $TOPIC_ARN" >> setup/values.yaml 

ret=$(aws sns get-topic-attributes --topic-arn $TOPIC_ARN --query 'Attributes.Policy')
if [ "$ret" = "null" ]; then 
    # 토픽 정책 설정 
    echo "Set topic policy."
    cat << EOF > /tmp/sns_policy.json 
    {
        "Version": "2008-10-17",
        "Id": "$POLICY_ID",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "s3.amazonaws.com"
                },
                "Action": [
                    "SNS:Publish"
                ],
                "Resource": "$TOPIC_ARN",
                "Condition": {
                    "ArnLike": {
                        "AWS:SourceArn": "$S3_BUCKET_ARN"
                    }
                }
            }
        ]
    }
EOF
    aws sns set-topic-attributes --topic-arn $TOPIC_ARN --attribute-name Policy --attribute-value "$(cat /tmp/sns_policy.json)"
else 
    echo "SNS Topic $SNS_TOPIC already has 'Policy' attribute."
fi 

ret=$( aws s3api get-bucket-notification-configuration --bucket $S3_BUCKET --query TopicConfigurations)
if [ "$ret" = "null" ]; then 
    # 버킷 알림 구성
    echo "Set bucket notification."
    cat << EOF > /tmp/notification_config.json
    {
        "TopicConfigurations": [
            {
                "Id": "$NOTI_ID",
                "TopicArn": "$TOPIC_ARN",
                "Events": ["s3:ObjectCreated:*"],
                "Filter": {
                    "Key": {
                        "FilterRules": [
                            {
                                "Name": "prefix",
                                "Value": "$S3_PREFIX"
                            }
                        ]
                    }
                }
            }
        ]
    }
EOF
    aws s3api put-bucket-notification-configuration --bucket $S3_BUCKET --notification-configuration file:///tmp/notification_config.json
else 
    echo "Bucket notification already exists."
fi 

# 알림 전용 IAM 유저 생성
ret=$(aws iam get-user --user-name $IAM_USER 2>&1)
if [ $? -eq 0 ]; then 
    echo "IAM user '$IAM_USER' already exists."
else
    echo "Create IAM User '$IAM_USER'"
    aws iam create-user --user-name $IAM_USER
    # 차트 설치를 위해 키 저장
    aws iam create-access-key --user-name $IAM_USER > /tmp/iam-key.json 
    echo "accessKey: "$(jq '.AccessKey.AccessKeyId' /tmp/iam-key.json | base64) >> setup/values.yaml
    echo "secretKey: "$(jq '.AccessKey.SecretAccessKey' /tmp/iam-key.json | base64) >> setup/values.yaml
    # rm /tmp/iam-key.json
fi 

ret=$(aws iam get-user-policy --user-name $IAM_USER --policy-name $USER_POLICY)
if [ "$ret" = "null" ]; then 
    # 유저가 SNS 토픽 이벤트를 받을유저 정책 있도록 정책 적용
    echo "Apply IAM policy '$USER_POLICY' to IAM user '$IAM_USER'"
    cat << EOF > /tmp/iam_policy.json
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": ["SNS:Subscribe", "SNS:ConfirmSubscription"],
                "Resource": "$TOPIC_ARN"
            }
        ]
    }
EOF
    # 유저 정책 적용
    aws iam put-user-policy --user-name $IAM_USER --policy-name $USER_POLICY --policy-document file:///tmp/iam_policy.json
else
    echo "User policy '$USER_POLICY' already exists for '$IAM_USER'."
fi 
