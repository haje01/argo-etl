# 1. OIDC 프로바이더 연동 
echo "Associate OIDC Provider with cluster."
eksctl utils associate-iam-oidc-provider \
    --region "ap-northeast-2" \
    --cluster prod \
    --approve

# 2. AWSLoadBalancerControllerIAMPolicy 설치 
ret=$(aws iam list-policies | grep AWSLoadBalancerControllerIAMPolicy)
if [ -z "$ret" ]; then
    echo "AWSLoadBalancerControllerIAMPolicy already exists."
else
    curl -s -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.4/docs/install/iam_policy.json
    echo "Create AWSLoadBalancerControllerIAMPolicy."
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file://iam_policy.json    
fi

# 3. 위 정책을 가지는 `AmazonEKSLoadBalancerControllerRole` 역할을 만들고,
# 그것과 연결된 쿠버네티스 서비스 어카운트를 생성
echo "Create AmazonEKSLoadBalancerControllerRole and IAM Service Account."
eksctl create iamserviceaccount \
  --cluster=prod \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name "AmazonEKSLoadBalancerControllerRole" \
  --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve
