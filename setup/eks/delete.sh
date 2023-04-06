#!/bin/sh

#
# EKS 클러스터 및 그것의 VPC 관련 리소스를 모두 제거 
#

set -e 

VPC_ID=vpc-022b89f5749a418fb

# EKS 클러스터 이름
EKS_CLUSTER=${EKS_CLUSTER?"Need to set EKS_CLUSTER"}

# EKS 클러스터의 VPC
VPC_ID=$(aws eks describe-cluster --name $EKS_CLUSTER | jq -r '.cluster.resourcesVpcConfig.vpcId')

# VPC 의 이름
VPC_NAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$VPC_ID" "Name=key,Values=Name" | jq -r '.Tags[0].Value')

# EKS 클러스터 삭제
eksctl delete cluster $EKS_CLUSTER 

# --wait 대신 지정 시간 대기 
sleep 30

#
# VPC 가 완전히 삭제되지 않고 남은 경우 관련 리소스와 함께 삭제
# 단, VPC 이름이 Default 가 아닌 경우만
# 

aws ec2 describe-vpcs --vpc-ids  "$VPC_ID" --query "Vpcs[*].State" --output text 2>/dev/null
if [ $? -ne 0 ]; then
    exit 0
fi

if [ "$VPC_NAME" = "Default" ]; then 
    exit 0
fi

echo "[ ] Delete VPC '$VPC_NAME' resources"

# 로드밸런서 삭제 (ALB 및 Network LB)
load_balancer_arns=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output json | jq -r '.[]')
for arn in $load_balancer_arns
do 
    echo "[ ] Delete load balancer '$arn'"
    aws elbv2 delete-load-balancer --load-balancer-arn "$arn"
    echo "[v] Delete load balancer '$arn'"
done

# 인터넷 게이트웨이 삭제
for igw in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].InternetGatewayId" --output text)
do
    echo "[ ] Delete internet gateway '$igw'"
    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID"
    aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
    echo "[v] Delete internet gateway '$igw'"
done 

# 서브넷 삭제
for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text)
do 
    echo "[ ] Delete subnet '$subnet'"
    aws ec2 delete-subnet --subnet-id "$subnet"
    echo "[v] Delete subnet '$subnet'"
done 

# 라우팅 테이블 및 보안 그룹은 VPC 와 함께 삭제되는듯

echo "[v] Delete VPC '$VPC_NAME' resources"

echo "[ ] Delete VPC '$VPC_ID'"
aws ec2 delete-vpc --vpc-id "$VPC_ID"
echo "[v] Delete VPC '$VPC_ID'"

# 클라우드 포메이션 스택 제거 
cfsname=$(aws cloudformation describe-stacks --query "Stacks[?Tags[?Key=='alpha.eksctl.io/cluster-name' && Value=='$EKS_CLUSTER']] | [0].StackName" --output text)
if [ "$cfsname" != "None" ]; then 
    echo "[ ] Delete CloudFormation stack '$cfsname'"
    aws cloudformation delete-stack --stack-name "$cfsname"
    echo "[v] Delete CloudFormation stack '$cfsname'"
fi
