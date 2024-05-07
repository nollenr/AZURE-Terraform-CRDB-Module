# AZURE-Terraform-CRDB-Module

![Resources Created in the Terraform HCL](resources/azure-single-regon.drawio.png)

Terraform HCL to create a multi-node CockroachDB cluster in Azure.   The number of nodes can be a multiple of 3 and nodes will be evenly distributed between 3 Azure Zones.   Optionally, you can include
 - haproxy VM - the proxy will be configured to connect to the cluster
 - app VM - application node that includes software for a multi-region demo

## Security Notes
- `firewalld` has been disabled on all nodes (cluster, haproxy and app).   
- A security group is created and assigned with ports 22, 8080 and 26257 opened to a single IP address.  The address is configurable as an input variable (my-ip-address)  

## Using the Terraform HCL
To use the HCL, you will need to define an Azure SSH Key -- that will be used for all VMs created to provide SSH access.

## Using ARM
You can provision a cluster using ARM but be careful on the availability of VM resources as the machine types may be limited or non-existant in some regions.  

### Run this Terraform Script
```terraform
# See the appendix below to intall Terrafrom, the Azure CLI and logging in to Azure

git clone https://github.com/nollenr/AZURE-Terraform-CRDB-Module.git
cd AZURE-Terraform-CRDB-Module/
```

#### if you intend to use enterprise features of the database 
```
export TF_VAR_cluster_organization={CLUSTER ORG}
export TF_VAR_enterprise_license={LICENSE}
```


#### Modify the terraform.tfvars to meet your needs

```
terraform init
terraform plan
terraform apply
```
To clean up and remove everything that was created

```
terraform destroy
```

### terraform variable crdb_resize_homelv
In Azure, any additional space allocated to a disk beyond the size of the image, is available but unused.  Setting the variable `crdb_resize_homelv` to "yes", will cause the user_data script to attempt to resize the home logical volume to take advantage of the additional space.  This is potentially dangerous and should only be used if you're sure that sda2 is the volume group with the homelv partition.  Typically, if you're using the standard redhat source image defined in by the instance.tf you should be fine.  

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

### pgworkload
To install pgworkload, be sure that the application instance has completed forming (check the .bashrc file for the function "PGWORKLOAD_INSTALL")
```
PGWORKLOAD_INSTALL
```

### UI Certificates
To avoid warnings from the browser when accessing the database UI, the server needs a cert signed by an authority recognized by the browser.  Let's Encrypt provides signed CAs at no charge.  

A function is installed in the `.bashrc` named `IUCERT`.  Running this function will install `snapd` and `certbot` which is used by Let's Encrypt to generate CA certificates.  

https://certbot.eff.org/instructions?ws=other&os=fedora 

https://snapcraft.io/docs/installing-snap-on-red-hat

https://letsencrypt.org/getting-started/

Please note that prior to running the function, you'll need to 
- open port 80 in the Network Security Group for certbot
- create a DNS 'A' Record for the domain -- the IP address will is the IP of the CRDB server
- edit the `UICERT` function and replace the domain on the `certbot` call with your domain name

## Making Sense of the TLS Certs Used in This HCL
There are a lot of TLS objects (see [tls HCL file](tls.tf) ).  To help make sense of the objects and how they are used in CRDB and VM formation, I created this chart to help -- maybe it does, maybe it doesn't.  
| Variable | CRDB  Name| TLS | TLS Name | Directory | Note |
| ------   | ----      | --- | -------- | ----------|  ---- |
| tls_private_key | ca.key | tls_private_key.crdb_ca_keys.private_key_pem | TLS Private Key PEM| my-safe-directory | Private key -- same key used by all nodes. |
|tls_public_key|ca.pub|tls_private_key.crdb_ca_keys.public_key_pem|TLS Public Key PEM| certs | cluster public key stored  in the certs directory.  for encoding messages. |
|tls_cert|ca.crt|tls_self_signed_cert.crdb_ca_cert.cert_pem|TLS Cert PEM| certs | certificate for authenticity |
|tls_self_signed_cert|ca.crt|tls_self_signed_cert.crdb_ca_cert.cert_pem|TLS Cert PEM| | Duplicate of tls_cert for better naming |
|tls_user_cert|client.name.crt|tls_locally_signed_cert.user_cert.cert_pem| certs | these are client certs for logging into the database (other than root's cert) | 
|tls_locally_signed_cert |client.name.crt |tls_locally_signed_cert.user_cert.cert_pem | | Duplicate of tls_user_cert for better naming
|tls_user_key|client.name.key|tls_private_key.client_keys.private_key_pem| cert | the client private key file associated with the client cert (other than root's cert) |



# Resource Group Creation Issue
Starting on 4/28/2024, there were problems with a new release of the terraform provider creating resource groups.   The return code to the terraform HCL is incorrect
```
╷
│ Error: Provider produced inconsistent result after apply
│
│ When applying changes to azurerm_resource_group.rg[0], provider "provider[\"registry.terraform.io/hashicorp/azurerm\"]" produced an unexpected new value: Root
│ object was present, but now absent.
│
│ This is a bug in the provider, which should be reported in the provider's own issue tracker.
╵

```
As a temporary workaround, until the provider is fixed, you can import the created resource group into the managed terraform state:
```
terraform import terraform_id azure_resource_id
```

```
terraform import "azurerm_resource_group.rg[0]" "/subscriptions/eebc0b2a-9ff2-499c-9e75-1a32e8fe13b3/resourceGroups/nollen-pgworkload-test-rg"
```

The `terraform_id` can be found in the error message and the `azure_resource_id` is available from the properties tab in the Azure UI for the resource group.

Once the resource group has been successfully imported, you can re-try `terrform apply`.
