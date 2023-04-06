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
IAM_USER="$PROJECT-sns-noti"
# IAM 유저 정책 이름
USER_POLICY="$PROJECT-sns-noti-policy"
# S3 정책 이름
S3_POLICY="$PROJECT-s3-policy"

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
    # 차트 설치를 위한 value 파일 생성 
    echo "topicArn: $TOPIC_ARN" > svals/topic-arn.yaml
else
    echo "SNS topic '$SNS_TOPIC' already exists."
    TOPIC_ARN="arn:aws:sns:ap-northeast-2:$AWS_ACCOUNT_ID:$SNS_TOPIC"
fi
echo "Topic ARN: $TOPIC_ARN"

# 토픽 기본 정책을 덮어쓰기 위해 매번 정책 설정
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

ret=$(aws s3api get-bucket-notification-configuration --bucket $S3_BUCKET --query TopicConfigurations)
if [ "$ret" = "null" ]; then 
    # 버킷 알림 구성
    echo "Set bucket notification."
    cat << EOF > /tmp/notification_config.json
{
    "TopicConfigurations": [
        {
            "Id": "$NOTI_ID",
            "TopicArn": "$TOPIC_ARN",
            "Events": ["s3:ObjectCreated:Put"],
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

# 인그레스 주소 얻기
ret=$(kubectl get ingress -l 'app.kubernetes.io/name=argo-workflows' --no-headers | awk '{print $4}')
echo "Ingress address '$ret'"
echo "ingressAddr: $ret" > /tmp/ingress-addr.yaml
# 이전 파일과 다를 때만 복사 (무한 배포 방지)
if [ ! -f svals/ingress-addr.yaml ] || ! cmp -s /tmp/ingress-addr.yaml svals/ingress-addr.yaml; then 
      echo "Overwrite to svals/ingress-addr.yaml"
    mv /tmp/ingress-addr.yaml svals/ingress-addr.yaml
fi 

#
# 노드그룹 역할에 필요한 정책 추가 
#

# 노드 그룹 및 역할
NODE_GROUP=$(aws eks list-nodegroups --cluster-name $EKS_CLUSTER --quer 'nodegroups[]' --output text)
NODE_ROLE_ARN=$(aws eks describe-nodegroup --cluster-name $EKS_CLUSTER --nodegroup-name $NODE_GROUP --query 'nodegroup.nodeRole' --output text)
NODE_ROLE=$(echo "$NODE_ROLE_ARN" | awk -F/ '{print $NF}')

# SNS 구독
echo "Apply SNS policy '$USER_POLICY' to node role '$NODE_ROLE'"
cat << EOF > /tmp/subscribe_policy.json
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
aws iam put-role-policy --role-name $NODE_ROLE --policy-name $S3_POLICY --policy-document file:///tmp/subscribe_policy.json
# ECR 저장소 읽기
aws iam attach-role-policy --role-name $NODE_ROLE --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
# S3 버킷에 읽고 쓰기 
echo "Apply S3 policy '$S3_POLICY' to node role '$NODE_ROLE'"
cat << EOF > /tmp/s3_policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::$S3_BUCKET",
                "arn:aws:s3:::$S3_BUCKET/*"
            ]
        }
    ]
}
EOF
aws iam put-role-policy --role-name $NODE_ROLE --policy-name $S3_POLICY --policy-document file:///tmp/s3_policy.json