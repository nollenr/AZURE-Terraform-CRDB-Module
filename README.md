# AZURE-Terraform-CRDB-Module

Terraform HCL to create a multi-node CockroachDB cluster in Azure.   The number of nodes can be a multiple of 3 and nodes will be evenly distributed between 3 Azure Zones.   Optionally, you can include
 - haproxy VM - the proxy will be configured to connect to the cluster
 - app VM - application node that includes software for a multi-region demo

Security Notes
firewalld has been disabled on all nodes (cluster, haproxy and app).    A security group is created and assigned with ports 22, 8080 and 26257 opened to a single IP address.  

To use the HCL, you will need to define an Azure SSH Key -- that will be used for all VMs created to provide SSH access.

### Run this Terraform Script
```terraform
# See the appendix below to intall Terrafrom, the Azure CLI and logging in to Azure

git clone https://github.com/nollenr/AZURE-Terraform-CRDB-Module.git
cd AZURE-Terraform-CRDB-Module/

# if you intend to use enterprise features of the database 
export TF_VAR_cluster_organization={CLUSTER ORG}
export TF_VAR_enterprise_license={LICENSE}

# Modify the terraform.tfvars to meet your needs

terraform init
terraform plan
terraform apply
terraform destroy
```



## Appendix 
### Finding images
```
az vm image list -p "Canonical"
az vm image list -p "Microsoft"
```
### AZURE Terraform - CockroachDB on VM

#### Install Terrafrom
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform

#### Install Azure CLI
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
for RHEL 8
sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
sudo dnf install azure-cli

az upgrade
az version
az login (directs you to a browser login with a code -- once authenticated, your credentials will be displayed in the terminal)

### Links:
Microsoft Terraform Docs
https://learn.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-terraform

Sizes for VM machines (not very helpful)
https://learn.microsoft.com/en-us/azure/virtual-machines/sizes

User Data that is a static SH 
https://github.com/guillermo-musumeci/terraform-azure-vm-bootstrapping-2/blob/master/linux-vm-main.tf

