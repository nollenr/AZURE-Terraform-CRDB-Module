# ----------------------------------------
# Globals
# ----------------------------------------
owner                      = "nollen"
resource_name              = "crdb-demo" # This is NOT the resource group name, but is used to form the resource group name unless it is passed in as multi-region-resource-group-name
multi_region               = false

# ----------------------------------------
# My IP Address - security group config
# ----------------------------------------
my_ip_address              = "98.148.51.154"

# Azure Locations: "australiacentral,australiacentral2,australiaeast,australiasoutheast,brazilsouth,brazilsoutheast,brazilus,canadacentral,canadaeast,centralindia,centralus,centraluseuap,eastasia,eastus,eastus2,eastus2euap,francecentral,francesouth,germanynorth,germanywestcentral,israelcentral,italynorth,japaneast,japanwest,jioindiacentral,jioindiawest,koreacentral,koreasouth,malaysiasouth,northcentralus,northeurope,norwayeast,norwaywest,polandcentral,qatarcentral,southafricanorth,southafricawest,southcentralus,southeastasia,southindia,swedencentral,swedensouth,switzerlandnorth,switzerlandwest,uaecentral,uaenorth,uksouth,ukwest,westcentralus,westeurope,westindia,westus,westus2,westus3,austriaeast,chilecentral,eastusslv,israelnorthwest,malaysiawest,mexicocentral,newzealandnorth,southeastasiafoundational,spaincentral,taiwannorth,taiwannorthwest"
# ----------------------------------------
# Resource Group
# ----------------------------------------
resource_group_location    = "westus2"

# ----------------------------------------
# Existing Key Info
# ----------------------------------------
azure_ssh_key_name           = "nollen-az-kp02"
azure_ssh_key_resource_group = "nollen-resource-group"

# ----------------------------------------
# Network
# ----------------------------------------
virtual_network_cidr       = "192.168.3.0/24"
virtual_network_location   = "westus2"

# ----------------------------------------
# CRDB Instance Specifications
# ----------------------------------------
# For ARM installs, you must choose the appropriate VM: Standard_D2ps_v5 (2vCPU), Standard_D4ps_v5, Standard_D8ps_v5, Standard_D16ps_v5, Standard_D32ps_v5, Standard_D48ps_v5, Standard_D64ps_v5
# crdb_vm_size               = "Standard_B1ms"   # amd64 chip (Standard) // 
crdb_vm_size               = "Standard_D4ps_v5"  # arm (Standard_D2ps_v5 and Standard_D4ps_v5 also allows spot pricing)
crdb_store_disk_size        = 64
crdb_nodes                 = 3
crdb_arm_release           = "yes"
crdb_enable_spot_instances = "no"

# ----------------------------------------
# CRDB Admin User - Cert Connection
# ----------------------------------------
create_admin_user          = "yes"
admin_user_name            = "ron"

# ----------------------------------------
# CRDB Specifications
# ----------------------------------------
# For ARM installs, the version must be 23.2.x and above.   
crdb_version                             = "24.2.0"
ua_archiecture_primary_cluster           = "no" # both primary and standby can be "no" for a single tenant "regular" cluster.  But if they are both yes, the the cluster will be initialized without any virtualized flag.
ua_archiecture_standby_cluster           = "no"
ua_archiecture_replication_user_name     = "repladmin"
ua_archiecture_replication_user_password = "repladmin123"

# ----------------------------------------
# Cluster Enterprise License Keys
# ----------------------------------------
# Be sure to do the following in your environment if you plan on installing the license keys
#   export TF_VAR_cluster_organization='your cluster organization'
#   export TF_VAR_enterprise_license='your enterprise license'
install_enterprise_keys   = "yes"

# ----------------------------------------
# HA Proxy Instance Specifications
# ----------------------------------------
include_ha_proxy           = "yes"
haproxy_vm_size            = "Standard_B1ms"

# ----------------------------------------
# APP Instance Specifications
# ----------------------------------------
include_app                = "yes"
app_vm_size                = "Standard_B1ms"
app_disk_size              = 64
app_resize_homelv          = "no"  # if the app_disk_size is greater than 64, then set this to "yes" so that the disk will be resized.  See warnings in vars.tf!

# ----------------------------------------
# Cluster Location Data - For console map
# ----------------------------------------
install_system_location_data = "yes"

# ----------------------------------------
# UI Cert (so that the database console does not issue "Your connection is not private" warning)
# ----------------------------------------
include_uicert             = "yes"
uicert_domain_name         = "crdb.nollen.click"
uicert_email_address       = "nollen@cockroachlabs.com"