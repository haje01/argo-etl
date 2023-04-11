#!/bin/sh

#
# eksctl delete cluster 후 남은 리소스 제거 
#

# EKS 클러스터 이름
EKS_CLUSTER=${EKS_CLUSTER?"Need to set EKS_CLUSTER"}
echo "Target EKS cluster '$EKS_CLUSTER'"

# 클라우드 스택 지우기
CL_STACK="eksctl-$EKS_CLUSTER-cluster"
ret=$(aws cloudformation describe-stacks --stack-name $CL_STACK 2>/dev/null)
if [ -n "$ret" ]; then 
    echo "[ ] Delete CloudFormation stack '$CL_STACK'"
    aws cloudformation delete-stack --stack-name $CL_STACK
    echo "[v] Delete CloudFormation stack '$CL_STACK'"
fi 

# EKS 클러스터가 있으면
ret=$(aws eks describe-cluster --name "$EKS_CLUSTER" 2>/dev/null)
if [ -n "$ret" ];  then
    # EKS 클러스터의 VPC
    VPC_ID=$(aws eks describe-cluster --name $EKS_CLUSTER | jq -r '.cluster.resourcesVpcConfig.vpcId')
    # VPC 의 이름
    VPC_NAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$VPC_ID" "Name=key,Values=Name" | jq -r '.Tags[0].Value')

    # EKS 클러스터의 노드그룹 삭제 
    for ng in $(aws eks list-nodegroups --cluster-name $EKS_CLUSTER --output text);
    do 
        echo "[ ] Delete node group '$ng'"
        aws eks delete-nodegroup --cluster-name $EKS_CLUSTER --nodegroup-name $ng
        if [ $? -eq 0 ]; then 
            echo "[v] Delete node group '$ng'"
        fi
    done 
else 
    echo "No EKS cluster '$EKS_CLUSTER' exists."
    VPC_NAME="eksctl-$EKS_CLUSTER-cluster/VPC"
    echo "Using inferenced VPC_NAME '$VPC_NAME'"
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId' --output text)
fi 

# 이후 작업은 VPC 이름이 Default 가 아닌 경우만 수행
if [ "$VPC_NAME" = "Default" ]; then 
    echo "Due to concerns, no further work on the Default VPC should be done."
    exit 0
fi

# 이후 작업은 VPC 가 존재하는 경우만 수행
if [ "$VPC_ID" = "None" ]; then 
    echo "VPC does not exists."
    exit 0
fi

# 로드밸런서 삭제 (ALB 및 Network LB)
load_balancer_arns=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output json | jq -r '.[]')
for arn in $load_balancer_arns
do 
    echo "[ ] Delete load balancer '$arn'"
    aws elbv2 delete-load-balancer --load-balancer-arn "$arn"
    echo "[v] Delete load balancer '$arn'"
    # 잠시 기다림
    sleep 10
done

# NAT 게이트웨이 삭제
for ngi in $(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[].NatGatewayId' --output text);
do 
    # NAT 게이트웨이가 연결된 모든 라우팅 테이블에서 
    for rti in $(aws ec2 describe-route-tables --filters "Name=route.gateway-id,Values=$ngi" --query 'RouteTables[].RouteTableId' --output text);
    do 
        # 해당 게이트웨이 라우팅 규칙을 제거
        echo "[ ] Delete routing $rgi' for NAT gateway '$ngi'"
        aws ec2 delete-route --route-table-id $rti --destination-cidr-block 0.0.0.0/0
        if [ $? -eq 0 ]; then 
            echo "[v] Delete routing $rgi' for NAT gateway '$ngi'"
        fi
    done 
    echo "[ ] Delete NAT gateway '$ngi'"

    # NAT 게이트웨이의 Elastic IP 주소 할당 
    ali=$(aws ec2 describe-nat-gateways --nat-gateway-ids $ngi --query 'NatGateways[].NatGatewayAddresses[].AllocationId' --output text)

    # NAT 게이트웨이를 삭제
    aws ec2 delete-nat-gateway --nat-gateway-id $ngi
    if [ $? -eq 0 ]; then 
        echo "[v] Delete NAT gateway '$ngi'"
    fi

    # Elastic IP 주소 할당이 존재하면 
    echo "Check IP Acclocation '$ali'"
    ret=$(aws ec2 describe-addresses --allocation-ids $ali --query 'Addresses[].AllocationId' --output text 2>/dev/null)
    if [ -n "$ret" ]; then 
        # Elastic IP 주소를 할당 취소
        echo "[ ] Release address allcation '$ali'"
        aws ec2 release-address --allocation-id $ali
        if [ $? -eq 0 ]; then 
            echo "[v] Release address allcation '$ali'"
        fi 
    fi
done 

# EKS 클러스터 VPC 내 모든 네트워크 인터페이스 Attachment 떼기
for nti in $(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text)
do 
    for atc in $(aws ec2 describe-network-interfaces --network-interface-ids $nti --query 'NetworkInterfaces[*].Attachment.AttachmentId' --output text)
    do 
        echo "[ ] Detach attachment '$atc' from network interface '$nti'"
        aws ec2 detach-network-interface --attachment-id $atc
        if [ $? -eq 0 ]; then 
            echo "[v] Detach attachment '$atc' from network interface '$nti'"
        fi 
    done
done

# 인터넷 게이트웨이 삭제
for igw in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].InternetGatewayId" --output text)
do
    echo "[ ] Detach internet gateway '$igw'"
    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID"
    if [ $? -eq 0 ]; then 
        echo "[v] Detach internet gateway '$igw'"
    fi
    echo "[ ] Delete internet gateway '$igw'"
    aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
    if [ $? -eq 0 ]; then 
        echo "[v] Delete internet gateway '$igw'"
    fi
done 

# EKS 클러스터 VPC 내 모든 네트워크 인터페이스 제거
for nti in $(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text)
do 
    echo "[ ] Delete network interface '$nti'"
    aws ec2 delete-network-interface --network-interface-id $nti
    if [ $? -eq 0 ]; then 
        echo "[v] Delete network interface '$nti'"
    fi
done

# 서브넷 삭제
for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text);
do 
    echo "[ ] Delete subnet '$subnet'"
    aws ec2 delete-subnet --subnet-id "$subnet"
    if [ $? -eq 0 ]; then 
        echo "[v] Delete subnet '$subnet'"
    fi
done 


# VPC 내의 모든 Security Group 삭제
for sgi in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[*].GroupId' --output text); 
do
    echo "[ ] Delete security group $sgi"
    aws ec2 delete-security-group --group-id $sgi
    if [ $? -eq 0 ]; then 
        echo "[v] Delete security group $sgi"
    fi
done

# VPC 삭제
echo "[ ] Delete VPC '$VPC_ID'"
aws ec2 delete-vpc --vpc-id "$VPC_ID"
if [ $? -eq 0 ]; then 
    echo "[v] Delete VPC '$VPC_ID'"
fi

# #
# # VPC 가 완전히 삭제되지 않고 남은 경우 관련 리소스와 함께 삭제
# # 단, VPC 이름이 Default 가 아닌 경우만
# # 

# aws ec2 describe-vpcs --vpc-ids  "$VPC_ID" --query "Vpcs[*].State" --output text 2>/dev/null
# if [ $? -ne 0 ]; then
#     exit 0
# fi

# echo "[ ] Delete VPC '$VPC_NAME' resources"

# # 로드밸런서 삭제 (ALB 및 Network LB)
# load_balancer_arns=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output json | jq -r '.[]')
# for arn in $load_balancer_arns
# do 
#     echo "[ ] Delete load balancer '$arn'"
#     aws elbv2 delete-load-balancer --load-balancer-arn "$arn"
#     echo "[v] Delete load balancer '$arn'"
# done

# # 서브넷에서 Public 주소 떼기
# for sn in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-0604a21e3d94c89c1" --query "Subnets[*].SubnetId" --output text)
# do
#     echo "[ ] Detach public IP from '$sn'"
#     aws ec2 modify-subnet-attribute --subnet-id $sn --no-map-public-ip-on-launch
#     echo "[v] Detach public IP from '$sn'"
# done

# # VPC 에서 Public 주소 떼기


# # 인터넷 게이트웨이 삭제
# for igw in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].InternetGatewayId" --output text)
# do
#     echo "[ ] Delete internet gateway '$igw'"
#     aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID"
#     aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
#     echo "[v] Delete internet gateway '$igw'"
# done 

# # 서브넷 삭제
# for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text)
# do 
#     echo "[ ] Delete subnet '$subnet'"
#     aws ec2 delete-subnet --subnet-id "$subnet"
#     echo "[v] Delete subnet '$subnet'"
# done 

# # 라우팅 테이블 및 보안 그룹은 VPC 와 함께 삭제되는듯

# echo "[v] Delete VPC '$VPC_NAME' resources"

# echo "[ ] Delete VPC '$VPC_ID'"
# aws ec2 delete-vpc --vpc-id "$VPC_ID"
# echo "[v] Delete VPC '$VPC_ID'"

# # 클라우드 포메이션 스택 제거 
# cfsname=$(aws cloudformation describe-stacks --query "Stacks[?Tags[?Key=='alpha.eksctl.io/cluster-name' && Value=='$EKS_CLUSTER']] | [0].StackName" --output text)
# if [ "$cfsname" != "None" ]; then 
#     echo "[ ] Delete CloudFormation stack '$cfsname'"
#     aws cloudformation delete-stack --stack-name "$cfsname"
#     echo "[v] Delete CloudFormation stack '$cfsname'"
# fi
