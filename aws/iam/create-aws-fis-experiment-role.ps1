. "..\..\shared\common-functions.ps1"

$Prefix='cesxs'
$Delimeter='-'
$GeneratedValue=Get-ShortId(Get-Random)
$Alias="<your alias>"
$OwnerTag="Key=Owner,Value=$Alias"
$AwsFisExperimentRoleName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'fis-role'
$AwsFisExperimentPolicyName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'fis-policy'

Write-Output "Creating role: '$AwsFisExperimentRoleName'"

# create an experiment role and add the trust policy
aws iam create-role `
    --role-name $AwsFisExperimentRoleName `
    --assume-role-policy-document file://.\fis-role-trust-policy.json `
    --tags $OwnerTag `
    --output text

Write-Output "Creating policy: '$AwsFisExperimentPolicyName'"

# create policy
$PolicyArn=$(aws iam create-policy `
    --policy-name $AwsFisExperimentPolicyName `
    --policy-document file://.\fis-role-permissions-policy.json `
    --tags $OwnerTag `
    --query 'Policy.Arn' `
    --output text)

Write-Output "Attaching policy '$AwsFisExperimentPolicyName' to role '$AwsFisExperimentRoleName'"

# attach the permissions policy
aws iam attach-role-policy `
    --role-name $AwsFisExperimentRoleName `
    --policy-arn $PolicyArn `
    --output text
