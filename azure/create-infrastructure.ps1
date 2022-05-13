. "..\..\shared\common-functions.ps1"

# Variables
$Prefix='cea'
$Delimeter='-'
$GeneratedValue=Get-ShortId(Get-Random)
$Alias="<your alias>"
$Tags="Owner=$Alias"
$Location='centralus'
$ResourceGroupName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'rg'
$VNetName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'vnet'
$SubnetName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'subnet'
$NsgName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'nsg'
$LoadBalancerName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'lb'
$PublicIPName=Get-ResourceName $Delimeter $Prefix $GeneratedValue 'publicip'
$LoadBalancerFrontEndIpName='frontendpool'
$LoadBalancerBackEndPoolName='backendpool'
$AvailabilitySetName='myAvailabilitySet'
$MyIP='67.167.197.28/32'

# Create resource group
# az group create `
#     --name $ResourceGroupName `
#     --location $Location `
#     --tags $Tags

# Create vnet
$VNetId=$(az network vnet create `
    --resource-group $ResourceGroupName `
    --name $VNetName `
    --location $Location `
    --subnet-name $SubnetName `
    --query "newVNet.id" `
    --output tsv `
    --tags $Tags)

# Create NSG
az network nsg create `
    --resource-group $ResourceGroupName `
    --name $NsgName `
    --location $Location `
    --tags $Tags

# Create NSG Rule
az network nsg rule create `
    --resource-group $ResourceGroupName `
    --nsg-name $NsgName `
    --name $($NsgName + '-SSH') `
    --priority 1010 `
    --protocol tcp `
    --source-address-prefixes $MyIP `
    --destination-port-range 22 

# Create NSG Rule
az network nsg rule create `
    --resource-group $ResourceGroupName `
    --nsg-name $NsgName `
    --name $($NsgName + '-HTTP') `
    --priority 1001 `
    --protocol tcp `
    --destination-port-range 80 

# Create public IP address
az network public-ip create `
    --resource-group $ResourceGroupName `
    --sku Standard `
    --name $PublicIPName `
    --location $Location `
    --tags $Tags

# Create Azure load balancer
az network lb create `
    --resource-group $ResourceGroupName `
    --name $LoadBalancerName `
    --frontend-ip-name $LoadBalancerFrontEndIpName `
    --backend-pool-name $LoadBalancerBackEndPoolName `
    --sku Standard `
    --public-ip-address $PublicIPName `
    --location $Location `
    --tags $Tags

# Create health probe
az network lb probe create `
    --resource-group $ResourceGroupName `
    --lb-name $LoadBalancerName `
    --name HealthProbe1 `
    --protocol tcp `
    --port 80

# Create load balancer rule
az network lb rule create `
    --resource-group $ResourceGroupName `
    --lb-name $LoadBalancerName `
    --name LoadBalancerRule1 `
    --protocol tcp `
    --frontend-port 80 `
    --backend-port 80 `
    --frontend-ip-name $LoadBalancerFrontEndIpName `
    --backend-pool-name $LoadBalancerBackEndPoolName `
    --probe-name HealthProbe1

# Create availability set
az vm availability-set create `
    --resource-group $ResourceGroupName `
    --name $AvailabilitySetName `
    --location $Location `
    --tags $Tags

# Create VMs
$privateIpAddrs = @()

for ($i=0; $i -lt 2; $i++)
{
    $privateIp=$(az vm create `
        --resource-group $ResourceGroupName `
        --name "$Prefix-$GeneratedValue-VM-$i" `
        --image UbuntuLTS `
        --admin-username azureuser `
        --availability-set $AvailabilitySetName `
        --generate-ssh-keys `
        --public-ip-sku Standard `
        --size standard_b1ms `
        --custom-data cloud-init.yml `
        --vnet-name $VNetName `
        --subnet $SubnetName `
        --tags $Tags `
        --nsg $NsgName `
        --location $Location `
        --query "privateIpAddress" `
        --output tsv)

    $privateIpAddrs+=$privateIp
}

az network lb address-pool update `
    --resource-group $ResourceGroupName `
    --lb-name $LoadBalancerName `
    --name $LoadBalancerBackEndPoolName `
    --vnet $VNetId `
    --backend-address name=addr1 ip-address=$($privateIpAddrs[0]) `
    --backend-address name=addr2 ip-address=$($privateIpAddrs[1])

# Test load balancer
$PublicIpAddr=$(az network public-ip show `
    --resource-group $ResourceGroupName `
    --name $PublicIPName `
    --query [ipAddress] `
    --output tsv)

$URL="http://$PublicIpAddr"
$Response = Invoke-WebRequest -URI $URL
Write-Host $Response.StatusCode
Write-Host $Response.Content
