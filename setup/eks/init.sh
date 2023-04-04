# EKS 클러스터 이름
EKS_CLUSTER=${EKS_CLUSTER?"Need to set EKS_CLUSTER"}

# 1. OIDC 프로바이더 연동 
ret=$(aws eks describe-cluster --name $EKS_CLUSTER | jq '.cluster.tags["alpha.eksctl.io/cluster-oidc-enabled"]' -r)
if [ "$ret" = "false" ]; then 
    echo "Associate OIDC Provider with cluster."
    eksctl utils associate-iam-oidc-provider \
        --region "ap-northeast-2" \
        --cluster $EKS_CLUSTER \
        --approve
else 
    echo "OIDC Provider already associated with cluster '$EKS_CLUSTER'."
fi 

# 2. AWSLoadBalancerControllerIAMPolicy 설치 
ret=$(aws iam list-policies | grep AWSLoadBalancerControllerIAMPolicy)
if [ -z "$ret" ]; then
    curl -s -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.4/docs/install/iam_policy.json
    echo "Create AWSLoadBalancerControllerIAMPolicy."
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file://iam_policy.json    
else
    echo "AWSLoadBalancerControllerIAMPolicy already exists."
fi

# 3. 위 정책을 가지는 `AmazonEKSLoadBalancerControllerRole` 역할을 만들고,
# 그것과 연결된 쿠버네티스 서비스 어카운트를 생성
ret=$(kubectl get sa aws-load-balancer-controller -n kube-system --ignore-not-found -o custom-columns=NAME:.metadata.name --no-headers)
if [ "$ret" = "aws-load-balancer-controller" ]; then 
    echo "IAM Service Account already exists."
else
    echo "Create IAM Service Account."
    eksctl create iamserviceaccount \
    --cluster=$EKS_CLUSTER \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --role-name "AmazonEKSLoadBalancerControllerRole" \
    --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
    --approve
fi