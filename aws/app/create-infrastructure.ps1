. "..\..\shared\common-functions.ps1"

# Variables
$Prefix='cea'
$Delimeter='-'
$GeneratedValue=Get-ShortId(Get-Random)
$Alias="<your alias>"
$OwnerTag="Key=Owner,Value=$Alias"
$VpcName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'vpc'
$LoadBalancerName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'lb'
$TargetGroupName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'tg'
$SecurityGroupName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'sg'
$WebServerName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'ws'
$VpcCidrBlock='10.0.0.0/16'
$Subnet1CidrBlock='10.0.0.0/20'
$Subnet2CidrBlock='10.0.16.0/20'
$MyIP='67.167.197.28/32'
$SshKeyName='<your keypair name for connecting to EC2 instances>'

# Create VPC
$VpcId=$(aws ec2 create-vpc `
  --cidr-block $VpcCidrBlock `
  --query 'Vpc.{VpcId:VpcId}' `
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VpcName},{$OwnerTag}]" `
  --output text)

# Enable DNS hostname
aws ec2 modify-vpc-attribute `
  --vpc-id $VpcId `
  --enable-dns-hostnames '{\"Value\":true}' `
  --output text

## Create subnets
$Subnet1Id=$(aws ec2 create-subnet `
  --vpc-id $VpcId --cidr-block $Subnet1CidrBlock `
  --availability-zone us-east-1a --query 'Subnet.{SubnetId:SubnetId}' `
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$VpcName-subnet1-us-east-1a},{$OwnerTag}]" `
  --output text)

$Subnet2Id=$(aws ec2 create-subnet `
  --vpc-id $VpcId --cidr-block $Subnet2CidrBlock `
  --availability-zone us-east-1b --query 'Subnet.{SubnetId:SubnetId}' `
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$VpcName-subnet2-us-east-1b},{$OwnerTag}]" `
  --output text)

# Enable Auto-assign Public IP on public subnets
aws ec2 modify-subnet-attribute `
    --subnet-id $Subnet1Id `
    --map-public-ip-on-launch `
    --output text

aws ec2 modify-subnet-attribute `
    --subnet-id $Subnet2Id `
    --map-public-ip-on-launch `
    --output text

# Create an Internet Gateway
$InternetGatewayId=$(aws ec2 create-internet-gateway `
  --query 'InternetGateway.{InternetGatewayId:InternetGatewayId}' `
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$VpcName-igw},{$OwnerTag}]" `
  --output text)

# Attach Internet gateway to your VPC
aws ec2 attach-internet-gateway `
  --vpc-id $VpcId `
  --internet-gateway-id $InternetGatewayId `
  --output text

# Create a route table
$CustomRouteTableId=$(aws ec2 create-route-table `
  --vpc-id $VpcId `
  --query 'RouteTable.{RouteTableId:RouteTableId}' `
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$VpcName-rt-public},{$OwnerTag}]" `
  --output text)

# Create route to Internet Gateway
aws ec2 create-route `
  --route-table-id $CustomRouteTableId `
  --destination-cidr-block 0.0.0.0/0 `
  --gateway-id $InternetGatewayId `
  --output text

# Associate subnets with route table (making them public subnets)
aws ec2 associate-route-table `
  --subnet-id $Subnet1Id `
  --route-table-id $CustomRouteTableId `
  --output text

aws ec2 associate-route-table `
  --subnet-id $Subnet2Id `
  --route-table-id $CustomRouteTableId `
  --output text

# Create a security group
aws ec2 create-security-group `
  --vpc-id $VpcId `
  --group-name $SecurityGroupName `
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SecurityGroupName},{$OwnerTag}]" `
  --description 'Non default security group' `
  --output text

# Get security group ID's
$DefaultSecurityGroupId=$(aws ec2 describe-security-groups `
  --filters "Name=vpc-id,Values=$VpcId" `
  --query 'SecurityGroups[?GroupName == `default`].GroupId' `
  --output text)

$CustomSecurityGroupId=$(aws ec2 describe-security-groups `
  --filters "Name=vpc-id,Values=$VpcId" `
  --query "SecurityGroups[?GroupName == '$SecurityGroupName'].GroupId" `
  --output text)

# Create security group ingress rules
aws ec2 authorize-security-group-ingress `
  --group-id $CustomSecurityGroupId `
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$MyIP}]" `
  --output text

aws ec2 authorize-security-group-ingress `
  --group-id $CustomSecurityGroupId `
  --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=$VpcCidrBlock}]" `
  --output text

aws ec2 authorize-security-group-ingress `
  --group-id $CustomSecurityGroupId `
  --ip-permissions "IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=$VpcCidrBlock}]" `
  --output text

aws ec2 authorize-security-group-ingress `
  --group-id $CustomSecurityGroupId `
  --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]" `
  --output text

# Add a tags to the default route table
$DefaultRouteTableId=$(aws ec2 describe-route-tables `
  --filters "Name=vpc-id,Values=$VpcId" `
  --query 'RouteTables[?Associations[0].Main != `false`].RouteTableId' `
  --output text)

aws ec2 create-tags `
  --resources $DefaultRouteTableId `
  --tags "Key=Name,Value=$VpcName-rt-default" "$OwnerTag" `
  --output text
  
# Add tags to default security groups
aws ec2 create-tags `
  --resources $DefaultSecurityGroupId `
  --tags "Key=Name,Value=$VpcName-sg-default" "$OwnerTag" `
  --output text

# Amazon Linux 2 AMI ID
$AMI_ID='ami-0f9fc25dd2506cf6d'

# Create EC2 instances
$AWS_EC2_INSTANCE1_ID=$(aws ec2 run-instances `
  --image-id $AMI_ID `
  --instance-type t2.micro `
  --key-name $SshKeyName `
  --monitoring "Enabled=true" `
  --security-group-ids $CustomSecurityGroupId `
  --subnet-id $Subnet1Id `
  --user-data file://.\userdata.txt `
  --query 'Instances[0].InstanceId' `
  --output text)

aws ec2 create-tags `
  --resources $AWS_EC2_INSTANCE1_ID `
  --tags "Key=Name,Value=$($WebServerName)1" "$OwnerTag"

$AWS_EC2_INSTANCE2_ID=$(aws ec2 run-instances `
  --image-id $AMI_ID `
  --instance-type t2.micro `
  --key-name $SshKeyName `
  --monitoring "Enabled=true" `
  --security-group-ids $CustomSecurityGroupId `
  --subnet-id $Subnet2Id `
  --user-data file://.\userdata.txt `
  --query 'Instances[0].InstanceId' `
  --output text)

aws ec2 create-tags `
  --resources $AWS_EC2_INSTANCE2_ID `
  --tags "Key=Name,Value=$($WebServerName)2" "$OwnerTag" `
  --output text

# Create load balancer
$AWS_LB_ID=$(aws elbv2 create-load-balancer `
  --name $LoadBalancerName `
  --subnets $Subnet1Id $Subnet2Id `
  --security-groups $CustomSecurityGroupId `
  --query 'LoadBalancers[0].LoadBalancerArn' `
  --output text)

aws elbv2 add-tags `
  --resource-arns $AWS_LB_ID `
  --tags "$OwnerTag" `
  --output text

# Create a target group
$AWS_TARGET_GROUP_ID=$(aws elbv2 create-target-group `
  --name $TargetGroupName `
  --protocol HTTP --port 80 `
  --vpc-id $VpcId `
  --ip-address-type ipv4 `
  --query 'TargetGroups[0].TargetGroupArn' `
  --output text)

aws elbv2 add-tags `
  --resource-arns $AWS_TARGET_GROUP_ID `
  --tags "$OwnerTag" `
  --output text

# Wait until EC2 instances are ready
aws ec2 wait instance-status-ok `
    --instance-ids $AWS_EC2_INSTANCE1_ID $AWS_EC2_INSTANCE2_ID

# Register targets
aws elbv2 register-targets `
  --target-group-arn $AWS_TARGET_GROUP_ID `
  --targets Id=$AWS_EC2_INSTANCE1_ID Id=$AWS_EC2_INSTANCE2_ID `
  --output text

# Create listener
aws elbv2 create-listener `
  --load-balancer-arn $AWS_LB_ID `
  --protocol HTTP --port 80 `
  --default-actions Type=forward,TargetGroupArn=$AWS_TARGET_GROUP_ID `
  --query 'Listeners[0].ListenerArn' `
  --output text

# Verify health of registered targets
aws elbv2 describe-target-health `
  --target-group-arn $AWS_TARGET_GROUP_ID `
  --output text

# Create interface Endpoints for SSM
aws ec2 create-vpc-endpoint `
  --vpc-id $VpcId `
  --vpc-endpoint-type Interface `
  --service-name com.amazonaws.us-east-1.ssm `
  --subnet-ids $Subnet1Id $Subnet2Id `
  --security-group-ids $DefaultSecurityGroupId $CustomSecurityGroupId `
  --private-dns-enabled `
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$VpcName-ssm-ep},{$OwnerTag}]" `
  --output text

aws ec2 create-vpc-endpoint `
  --vpc-id $VpcId `
  --vpc-endpoint-type Interface `
  --service-name com.amazonaws.us-east-1.ec2messages `
  --subnet-ids $Subnet1Id $Subnet2Id `
  --security-group-ids $DefaultSecurityGroupId $CustomSecurityGroupId `
  --private-dns-enabled `
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$VpcName-ec2messages-ep},{$OwnerTag}]" `
  --output text

aws ec2 create-vpc-endpoint `
  --vpc-id $VpcId `
  --vpc-endpoint-type Interface `
  --service-name com.amazonaws.us-east-1.ssmmessages `
  --subnet-ids $Subnet1Id $Subnet2Id `
  --security-group-ids $DefaultSecurityGroupId $CustomSecurityGroupId `
  --private-dns-enabled `
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$VpcName-ssmmessages-ep},{$OwnerTag}]" `
  --output text

# Grab load balancer DNS Name
$LoadBalancerDNSName=$(aws elbv2 describe-load-balancers `
  --load-balancer-arns $AWS_LB_ID `
  --query 'LoadBalancers[0].DNSName' `
  --output text)

$URL="http://$LoadBalancerDNSName"
$Response = Invoke-WebRequest -URI $URL
Write-Host $Response.StatusCode
Write-Host $Response.Content
