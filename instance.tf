# TODO:  CRDB instances greater than 3
locals {
  zones = ["1", "2", "3"]
  admin_username = "adminuser"
}

locals {
  ip_list     = join(" ", azurerm_network_interface.crdb_network_interface[*].private_ip_address)
  join_string = (var.join_string != "" ? var.join_string : join(",", azurerm_network_interface.crdb_network_interface[*].private_ip_address))
}

locals {
  source_image_reference_offer      = (var.crdb_arm_release == "no" ? "RHEL" : "rhel-arm64")
  source_image_reference_sku        = (var.crdb_arm_release == "no" ? "8-lvm-gen2" : "8_7-arm64") 
}

data "azurerm_ssh_public_key" "ssh_key" {
  name                = var.azure_ssh_key_name
  resource_group_name = var.azure_ssh_key_resource_group
}

resource "azurerm_public_ip" "crdb-ip" {
  count                        = var.crdb_nodes
  name                         = "${var.owner}-${var.resource_name}-public-ip-${count.index}"
  location                     = var.virtual_network_location
  resource_group_name          = local.resource_group_name
  allocation_method            = "Static"
  zones                        = [element(local.zones, count.index)]
  sku                          = "Standard"
  tags                         = local.tags
}

resource "azurerm_network_interface" "crdb_network_interface" {
  count                     = var.crdb_nodes
  name                      = "${var.owner}-${var.resource_name}-ni-${count.index}"
  location                  = var.virtual_network_location
  resource_group_name       = local.resource_group_name
  tags                      = local.tags

  ip_configuration {
    name                          = "${var.owner}-${var.resource_name}-ip-${count.index}"
    subnet_id                     = azurerm_subnet.sn[count.index%3].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.crdb-ip[count.index].id
  }
}

resource "azurerm_managed_disk" "data_disk" {
  count                = var.create_ec2_instances == "yes" ? var.crdb_nodes : 0
  name                 = "${var.owner}-${var.resource_name}-storagedisk-${count.index}"
  location             = var.virtual_network_location
  zone                 = local.zones[count.index%3]
  resource_group_name  = local.resource_group_name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.crdb_store_disk_size
}

resource "azurerm_virtual_machine_data_disk_attachment" "data_disk_attachment" {
  count              = var.create_ec2_instances == "yes" ? var.crdb_nodes : 0
  managed_disk_id    = azurerm_managed_disk.data_disk[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.crdb-instance[count.index].id
  lun                = "1"
  caching            = "ReadWrite"
}

resource "azurerm_linux_virtual_machine" "crdb-instance" {
  count                 = var.create_ec2_instances == "yes" ? var.crdb_nodes : 0
  name                  = "${var.owner}-${var.resource_name}-vm-crdb-${count.index}"
  location              = var.virtual_network_location
  resource_group_name   = local.resource_group_name
  size                  = var.crdb_vm_size
  tags                  = local.tags
  zone                  = local.zones[count.index%3]

  priority              = (var.crdb_enable_spot_instances == "no" ? "Regular" : "Spot")
  eviction_policy       = (var.crdb_enable_spot_instances == "no" ? null : "Delete")
  network_interface_ids = [azurerm_network_interface.crdb_network_interface[count.index].id]

  admin_username                  = local.admin_username     # is this still required with an admin_ssh key block?
  disable_password_authentication = true
  admin_ssh_key {
    username                      = local.admin_username    # a bug in the provider requires this to be adminuser
    public_key                    = data.azurerm_ssh_public_key.ssh_key.public_key
  }

  source_image_reference {
    offer     = local.source_image_reference_offer
    publisher = "RedHat"
    sku       = local.source_image_reference_sku
    version   = "latest"
  }

  os_disk {
    # do I assume this disk is deleted when the vm is deleted?  
    name      = "${var.owner}-${var.resource_name}-osdisk-${count.index}"
    caching   = "ReadWrite" # possible values: None, ReadOnly and ReadWrite
    storage_account_type = "Premium_LRS" # possible values: Standard_LRS, StandardSSD_LRS, Premium_LRS, Premium_SSD, StandardSSD_ZRS and Premium_ZRS
    disk_size_gb = 64
  }

  # echo "export ip_local=\`curl -H Metadata:true --noproxy \"*\" \"http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2017-08-01&format=text\"\`" >> /home/${local.admin_username}/.bashrc
  # echo "export azure_region=\`curl -s -H Metadata:true --noproxy \"*\" \"http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text\"\`" >> /home/${local.admin_username}/.bashrc

  user_data = base64encode(<<EOF
#!/bin/bash -xe

# Prepare, Mount, and Add a Disk to fstab (with XFS formatting and disk check)
# 1. Set disk information 
DISK_NAME="/dev/sdb"
MOUNT_POINT="/mnt/data"
# 2. Check if the disk exists (and retry a couple of times before failing)
MAX_RETRIES=121
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ -b "$DISK_NAME" ]; then
        echo "Disk $DISK_NAME found!"
        break  # Exit the loop if the disk is found
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "Disk $DISK_NAME not found. Retrying in 2 seconds... (Attempt $RETRY_COUNT/$MAX_RETRIES)"
        sleep 2
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "Error: Disk $DISK_NAME not found after $MAX_RETRIES retries."
    exit 1
fi

# 3. Partition the disk (if not already partitioned)
echo "Checking if $DISK_NAME is partitioned..."
if ! parted -s "$DISK_NAME" print | grep -q "^ 1"; then
    echo "Partitioning $DISK_NAME..."
    parted -s "$DISK_NAME" mklabel gpt # Create a GPT partition table
    parted -s "$DISK_NAME" mkpart primary 0% 100% # Create a single primary partition using all available space
    DISK_PARTITION="$${DISK_NAME}1" # Assuming the first partition is created
else
    echo "$DISK_NAME is already partitioned."
    DISK_PARTITION=$DISK_NAME$(parted -s "$DISK_NAME" print | awk '/^ 1 / {print $1}') # Get the first partition
fi
# 4. Format the partition with XFS
echo "Formatting $DISK_PARTITION with XFS..."
mkfs.xfs -f "$DISK_PARTITION"
if [ $? -ne 0 ]; then
    echo "Error: Failed to format $DISK_PARTITION."
    exit 1
fi
# 5. Create mount point if it doesn't exist
if [ ! -d "$MOUNT_POINT" ]; then
    echo "Creating mount point $MOUNT_POINT..."
    mkdir -p "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create mount point $MOUNT_POINT."
        exit 1
    fi
fi
# 6. Mount the partition and change permissions
echo "Mounting $DISK_PARTITION to $MOUNT_POINT..."
mount "$DISK_PARTITION" "$MOUNT_POINT"
if [ $? -ne 0 ]; then
    echo "Error: Failed to mount $DISK_PARTITION to $MOUNT_POINT."
    exit 1
fi
sudo chown adminuser:adminuser /mnt/data

# 7. Get UUID of the partition
UUID=$(blkid -s UUID -o value "$DISK_PARTITION")
# 8. Add entry to fstab (with XFS)
echo "Adding entry to /etc/fstab..."
echo "UUID=$UUID $MOUNT_POINT xfs defaults 0 2" | tee -a /etc/fstab
echo "Disk $DISK_NAME (partition $DISK_PARTITION) successfully prepared, mounted to $MOUNT_POINT, and added to fstab."

echo "Shutting down and disabling firewalld -- SECURITY RISK!!"
systemctl stop firewalld
systemctl disable firewalld
echo "Setting variables"
echo "export COCKROACH_CERTS_DIR=/home/${local.admin_username}/certs" >> /home/${local.admin_username}/.bashrc
echo 'export CLUSTER_PRIVATE_IP_LIST="${local.ip_list}" ' >> /home/${local.admin_username}/.bashrc
export CLUSTER_PRIVATE_IP_LIST="${local.ip_list}"
echo 'export JOIN_STRING="${local.join_string}" ' >> /home/${local.admin_username}/.bashrc
echo "export ip_local=${azurerm_network_interface.crdb_network_interface[count.index].private_ip_address}" >> /home/${local.admin_username}/.bashrc
echo "export ip_public=${azurerm_public_ip.crdb-ip[count.index].ip_address }" >> /home/${local.admin_username}/.bashrc
echo "export azure_region=${var.virtual_network_location}" >> /home/${local.admin_username}/.bashrc
echo "export azure_zone=\"${var.virtual_network_location}-${local.zones[count.index%3]}\"" >> /home/${local.admin_username}/.bashrc
echo "export CRDBNODE=${count.index}" >> /home/${local.admin_username}/.bashrc
export CRDBNODE=${count.index}
counter=1;for IP in $CLUSTER_PRIVATE_IP_LIST; do echo "export NODE$counter=$IP" >> /home/${local.admin_username}/.bashrc; (( counter++ )); done

echo "Downloading and installing CockroachDB along with the Geo binaries"
if [ "${var.crdb_arm_release}" = "no" ]
then
  curl https://binaries.cockroachdb.com/cockroach-v${var.crdb_version}.linux-amd64.tgz | tar -xz && cp -i cockroach-v${var.crdb_version}.linux-amd64/cockroach /usr/local/bin/
  mkdir -p /usr/local/lib/cockroach
  cp -i cockroach-v${var.crdb_version}.linux-amd64/lib/libgeos.so /usr/local/lib/cockroach/
  cp -i cockroach-v${var.crdb_version}.linux-amd64/lib/libgeos_c.so /usr/local/lib/cockroach/
else
  curl https://binaries.cockroachdb.com/cockroach-v${var.crdb_version}.linux-arm64.tgz | tar -xz && cp -i cockroach-v${var.crdb_version}.linux-arm64/cockroach /usr/local/bin/
  mkdir -p /usr/local/lib/cockroach
  cp -i cockroach-v${var.crdb_version}.linux-arm64/lib/libgeos.so /usr/local/lib/cockroach/
  cp -i cockroach-v${var.crdb_version}.linux-arm64/lib/libgeos_c.so /usr/local/lib/cockroach/
fi

echo "Creating the public and private keys"
su ${local.admin_username} -c 'mkdir /home/${local.admin_username}/certs; mkdir /home/${local.admin_username}/my-safe-directory'
echo '${local.tls_private_key}' >> /home/${local.admin_username}/my-safe-directory/ca.key
echo '${local.tls_public_key}' >> /home/${local.admin_username}/certs/ca.pub
echo '${local.tls_cert}}' >> /home/${local.admin_username}/certs/ca.crt

echo "Changing ownership on permissions on keys and certs"
chown ${local.admin_username}:${local.admin_username} /home/${local.admin_username}/certs/ca.crt
chown ${local.admin_username}:${local.admin_username} /home/${local.admin_username}/certs/ca.pub
chown ${local.admin_username}:${local.admin_username} /home/${local.admin_username}/my-safe-directory/ca.key
chmod 640 /home/${local.admin_username}/certs/ca.crt
chmod 640 /home/${local.admin_username}/certs/ca.pub
chmod 600 /home/${local.admin_username}/my-safe-directory/ca.key     

echo "Copying the ca.key to .ssh/id_rsa, generating the public key and adding it to authorized keys for passwordless ssh between nodes"
cp /home/${local.admin_username}/my-safe-directory/ca.key /home/${local.admin_username}/.ssh/id_rsa
ssh-keygen -y -f /home/${local.admin_username}/.ssh/id_rsa >> /home/${local.admin_username}/.ssh/authorized_keys
chown ${local.admin_username}:${local.admin_username} /home/${local.admin_username}/.ssh/id_rsa

echo "Creating the CREATENODECERT bashrc function"
echo "CREATENODECERT() {" >> /home/${local.admin_username}/.bashrc
echo "  cockroach cert create-node \\" >> /home/${local.admin_username}/.bashrc
echo '  $ip_local \' >> /home/${local.admin_username}/.bashrc
echo '  $ip_public \' >> /home/${local.admin_username}/.bashrc
echo "  localhost \\" >> /home/${local.admin_username}/.bashrc
echo "  127.0.0.1 \\" >> /home/${local.admin_username}/.bashrc
echo "Adding haproxy to the CREATENODECERT function if var.include_ha_proxy is yes"
if [ "${var.include_ha_proxy}" = "yes" ]; then echo "  ${azurerm_network_interface.haproxy[0].private_ip_address} \\" >> /home/${local.admin_username}/.bashrc; fi
echo "  --certs-dir=certs \\" >> /home/${local.admin_username}/.bashrc
echo "  --ca-key=my-safe-directory/ca.key" >> /home/${local.admin_username}/.bashrc
echo "}" >> /home/${local.admin_username}/.bashrc

echo "Creating the CREATEROOTCERT bashrc function"
echo "CREATEROOTCERT() {" >> /home/${local.admin_username}/.bashrc
echo "  cockroach cert create-client \\" >> /home/${local.admin_username}/.bashrc
echo '  root \' >> /home/${local.admin_username}/.bashrc
echo "  --certs-dir=certs \\" >> /home/${local.admin_username}/.bashrc
echo "  --ca-key=my-safe-directory/ca.key" >> /home/${local.admin_username}/.bashrc
echo "}" >> /home/${local.admin_username}/.bashrc   

if [ "${var.include_uicert}" = "yes" ]
then
echo "Let's Encrypt - snapd and certbot - for database ui certs"
echo "Creating the UICERT bashrc function"
echo "UICERT() {" >> /home/${local.admin_username}/.bashrc
echo "    echo 'The DNS A Record must be set in order for correct resolution of the name.  In AWS, navigate to Hosted Zones  in Route 53.' " >> /home/${local.admin_username}/.bashrc
echo "    sudo yum update -y --disablerepo='*' --enablerepo='*microsoft*' " >> /home/${local.admin_username}/.bashrc
echo "    sudo dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y" >> /home/${local.admin_username}/.bashrc
echo "    sudo yum install snapd -y" >> /home/${local.admin_username}/.bashrc
echo "    sudo systemctl enable --now snapd.socket" >> /home/${local.admin_username}/.bashrc
echo "    sudo ln -s /var/lib/snapd/snap /snap" >> /home/${local.admin_username}/.bashrc
echo "    sudo systemctl restart snapd.seeded.service" >> /home/${local.admin_username}/.bashrc
echo "    sudo snap install --classic certbot" >> /home/${local.admin_username}/.bashrc
echo "    sudo ln -s /snap/bin/certbot /usr/bin/certbot" >> /home/${local.admin_username}/.bashrc
echo "    sudo certbot certonly --standalone --non-interactive --agree-tos -m ${var.uicert_email_address} -d ${var.uicert_domain_name}" >> /home/${local.admin_username}/.bashrc
echo "    sudo cp /etc/letsencrypt/live/crdb.nollen.click/cert.pem /home/adminuser/certs/ui.crt" >> /home/${local.admin_username}/.bashrc
echo "    sudo cp /etc/letsencrypt/live/crdb.nollen.click/privkey.pem /home/adminuser/certs/ui.key" >> /home/${local.admin_username}/.bashrc
echo "    sudo chown adminuser:adminuser /home/adminuser/certs/ui.*" >> /home/${local.admin_username}/.bashrc
echo "    pkill -SIGHUP -x cockroach" >> /home/${local.admin_username}/.bashrc
echo "}" >> /home/${local.admin_username}/.bashrc   
fi

echo "Creating the STARTCRDB bashrc function"
echo "STARTCRDB() {" >> /home/${local.admin_username}/.bashrc
echo "  cockroach start \\" >> /home/${local.admin_username}/.bashrc
echo '  --locality=region="$azure_region",zone="$azure_zone" \' >> /home/${local.admin_username}/.bashrc
echo "  --certs-dir=certs \\" >> /home/${local.admin_username}/.bashrc
echo '  --advertise-addr=$ip_local \' >> /home/${local.admin_username}/.bashrc
echo '  --join=$JOIN_STRING \' >> /home/${local.admin_username}/.bashrc
echo '  --max-offset=250ms \' >> /home/${local.admin_username}/.bashrc
echo '  --store=/mnt/data \' >> /home/${local.admin_username}/.bashrc
echo "  --background " >> /home/${local.admin_username}/.bashrc
echo " }" >> /home/${local.admin_username}/.bashrc

echo "Creating the node cert, root cert and starting CRDB"
sleep 20; su ${local.admin_username} -lc 'CREATENODECERT; CREATEROOTCERT; STARTCRDB'

echo "SETCRDBVARS() {" >> /home/${local.admin_username}/.bashrc
echo "  cockroach node status | awk -F ':' 'FNR > 1 { print \$1 }' | awk '{ print \$1, \$2 }' |  while read line; do" >> /home/${local.admin_username}/.bashrc
echo "    node_number=\`echo \$line | awk '{ print \$1 }'\`" >> /home/${local.admin_username}/.bashrc
echo "    variable_name=CRDBNODE\$node_number" >> /home/${local.admin_username}/.bashrc
echo "    ip=\`echo \$line | awk '{ print \$2 }'\`" >> /home/${local.admin_username}/.bashrc
echo "    echo export \$variable_name=\$ip >> crdb_node_list" >> /home/${local.admin_username}/.bashrc
echo "  done" >> /home/${local.admin_username}/.bashrc
echo "  source ./crdb_node_list" >> /home/${local.admin_username}/.bashrc
echo "}" >> /home/${local.admin_username}/.bashrc

echo "Validating if init needs to be run"
echo "RunInit: ${var.run_init}  Count.Index: ${count.index}   Count: ${var.crdb_nodes}"
if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} ]]; then
  if [[ '${var.ua_archiecture_primary_cluster}' = 'yes' && ${var.ua_archiecture_standby_cluster} = 'yes' ]]; then echo "Initializing Cockroach Database" && su ${local.admin_username} -lc 'cockroach init';
  elif [[ '${var.ua_archiecture_primary_cluster}' = 'yes' ]]; then echo "Initializing Cockroach Database" && su ${local.admin_username} -lc 'cockroach init --virtualized'; 
  elif [[ '${var.ua_archiecture_standby_cluster}' = 'yes' ]]; then echo "Initializing Cockroach Database" && su ${local.admin_username} -lc 'cockroach init --virtualized-empty'; 
  else echo "Initializing Cockroach Database" && su ${local.admin_username} -lc 'cockroach init';
  fi
fi

if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.create_admin_user} = 'yes' && ${var.ua_archiecture_standby_cluster} = 'no' ]]; then echo "Creating admin user ${var.admin_user_name}" && su ${local.admin_username} -lc 'cockroach sql --execute "create user ${var.admin_user_name}; grant admin to ${var.admin_user_name} with admin option"'; fi

system_tenant_command1='cockroach sql --url "postgresql://root@${azurerm_network_interface.crdb_network_interface[count.index].private_ip_address}:26257?options=-ccluster=system" --execute "SET CLUSTER SETTING cluster.organization = '\''${var.cluster_organization}'\''; "'
system_tenant_command2='cockroach sql --url "postgresql://root@${azurerm_network_interface.crdb_network_interface[count.index].private_ip_address}:26257?options=-ccluster=system" --execute "SET CLUSTER SETTING enterprise.license = '\''${var.enterprise_license}'\''; "'
system_tenant_command3='cockroach sql --url "postgresql://root@${azurerm_network_interface.crdb_network_interface[count.index].private_ip_address}:26257?options=-ccluster=system" --execute "SET CLUSTER SETTING kv.rangefeed.enabled = true; "'
system_tenant_command4='cockroach sql --url "postgresql://root@${azurerm_network_interface.crdb_network_interface[count.index].private_ip_address}:26257?options=-ccluster=system" --execute "CREATE USER ${var.ua_archiecture_replication_user_name} WITH PASSWORD '\''${var.ua_archiecture_replication_user_password}'\''; GRANT SYSTEM REPLICATION TO ${var.ua_archiecture_replication_user_name}; "'

if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_enterprise_keys} = 'yes' ]]; then 
  echo "Installing enterprise license keys: ${var.cluster_organization} & ${var.enterprise_license}" 
  if [[ '${var.ua_archiecture_primary_cluster}' = 'yes' || '${var.ua_archiecture_standby_cluster}' = 'yes' ]]; then
    su ${local.admin_username} -lc "$system_tenant_command1"
    su ${local.admin_username} -lc "$system_tenant_command2"
    su ${local.admin_username} -lc "$system_tenant_command3"
    su ${local.admin_username} -lc "$system_tenant_command4"
  else 
    su ${local.admin_username} -lc 'cockroach sql --execute "SET CLUSTER SETTING cluster.organization = '\''${var.cluster_organization}'\''; "'
    su ${local.admin_username} -lc 'cockroach sql --execute "SET CLUSTER SETTING enterprise.license = '\''${var.enterprise_license}'\''; "'
  fi
fi

if [[ ${var.ua_archiecture_standby_cluster} = 'no' ]]; then
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''eastasia'\'', 22.267, 114.188);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''southeastasia'\'', 1.283, 103.833);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''centralus'\'', 41.5908, -93.6208);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''eastus'\'', 37.3719, -79.8164);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''eastus2'\'', 36.6681, -78.3889);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''westus'\'', 37.783, -122.417);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''northcentralus'\'', 41.8819, -87.6278);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''southcentralus'\'', 29.4167, -98.5);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''northeurope'\'', 53.3478, -6.2597);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''westeurope'\'', 52.3667, 4.9);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''japanwest'\'', 34.6939, 135.5022);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''japaneast'\'', 35.68, 139.77);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''brazilsouth'\'', -23.55, -46.633);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''australiaeast'\'', -33.86, 151.2094);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''australiasoutheast'\'', -37.8136, 144.9631);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''southindia'\'', 12.9822, 80.1636);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''centralindia'\'', 18.5822, 73.9197);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''westindia'\'', 19.088, 72.868);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''canadacentral'\'', 43.653, -79.383);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''canadaeast'\'', 46.817, -71.217);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''uksouth'\'', 50.941, -0.799);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''ukwest'\'', 53.427, -3.084);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''westcentralus'\'', 40.890, -110.234);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''westus2'\'', 47.233, -119.852);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''koreacentral'\'', 37.5665, 126.9780);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''koreasouth'\'', 35.1796, 129.0756);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''francecentral'\'', 46.3772, 2.3730);"'; fi
  if [[ '${var.run_init}' = 'yes' && ${count.index + 1} -eq ${var.crdb_nodes} && ${var.install_system_location_data} = 'yes' ]]; then echo "Installing system.locations in the database" && su ${local.admin_username} -lc 'cockroach sql --execute "INSERT into system.locations VALUES ('\''region'\'', '\''francesouth'\'', 43.8345, 2.1972);"'; fi
fi
  EOF
)
  
}
