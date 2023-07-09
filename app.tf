resource "azurerm_public_ip" "app-ip" {
    count                        = var.include_app == "yes" ? 1 : 0
    name                         = "${var.owner}-${var.resource_name}-public-ip-app"
    location                     = var.virtual_network_location
    resource_group_name          = local.resource_group_name
    allocation_method            = "Dynamic"
    sku                          = "Basic"
    tags                         = local.tags
}

resource "azurerm_network_interface" "app" {
    count                       = var.include_app == "yes" ? 1 : 0
    name                        = "${var.owner}-${var.resource_name}-ni-app"
    location                    = var.virtual_network_location
    resource_group_name         = local.resource_group_name
    tags                        = local.tags

    ip_configuration {
    name                          = "network-interface-app-ip"
    subnet_id                     = azurerm_subnet.sn[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app-ip[0].id
    }
}


resource "azurerm_linux_virtual_machine" "app" {
    count                 = var.include_app == "yes" ? 1 : 0
    name                  = "${var.owner}-${var.resource_name}-vm-app"
    location              = var.virtual_network_location
    resource_group_name   = local.resource_group_name
    size                  = var.haproxy_vm_size
    tags                  = local.tags

    network_interface_ids = [azurerm_network_interface.app[0].id]

    admin_username                  = local.admin_username     # is this still required with an admin_ssh key block?
    disable_password_authentication = true
    admin_ssh_key {
        username                      = local.admin_username    # a bug in the provider requires this to be adminuser
        public_key                    = data.azurerm_ssh_public_key.ssh_key.public_key
    }

    source_image_reference {
        offer     = "RHEL"
        publisher = "RedHat"
        sku       = "8-lvm-gen2"
        version   = "latest"
    }

    os_disk {
        name      = "${var.owner}-${var.resource_name}-osdisk-app"
        caching   = "ReadWrite" # possible values: None, ReadOnly and ReadWrite
        storage_account_type = "Standard_LRS" # possible values: Standard_LRS, StandardSSD_LRS, Premium_LRS, Premium_SSD, StandardSSD_ZRS and Premium_ZRS
    }

    user_data = base64encode(<<EOF
#!/bin/bash -xe
echo "Shutting down and disabling firewalld -- SECURITY RISK!!"
systemctl stop firewalld
systemctl disable firewalld
yum install git -y
su ${local.admin_username} -c 'mkdir /home/${local.admin_username}/certs'
echo '${local.tls_cert}' >> /home/${local.admin_username}/certs/ca.crt 
chown ${local.admin_username}:${local.admin_username} /home/${local.admin_username}/certs/ca.crt
chmod 600 /home/${local.admin_username}/certs/ca.crt
echo '${local.tls_user_cert}' >> /home/${local.admin_username}/certs/client.${var.admin_user_name}.crt
chown ${local.admin_username}:${local.admin_username} /home/${local.admin_username}/certs/client.${var.admin_user_name}.crt
chmod 600 /home/${local.admin_username}/certs/client.${var.admin_user_name}.crt
echo '${local.tls_user_key}' >> /home/${local.admin_username}/certs/client.${var.admin_user_name}.key
chown ${local.admin_username}:${local.admin_username} /home/${local.admin_username}/certs/client.${var.admin_user_name}.key
chmod 600 /home/${local.admin_username}/certs/client.${var.admin_user_name}.key

echo "Downloading and installing CockroachDB along with the Geo binaries"
curl https://binaries.cockroachdb.com/cockroach-sql-v${var.crdb_version}.linux-amd64.tgz | tar -xz && cp -i cockroach-sql-v${var.crdb_version}.linux-amd64/cockroach-sql /usr/local/bin/

echo "CRDB() {" >> /home/${local.admin_username}/.bashrc
echo 'cockroach-sql sql --url "postgresql://${var.admin_user_name}@'"${azurerm_network_interface.haproxy[0].private_ip_address}:26257/defaultdb?sslmode=verify-full&sslrootcert="'$HOME/certs/ca.crt&sslcert=$HOME/certs/client.'"${var.admin_user_name}.crt&sslkey="'$HOME/certs/client.'"${var.admin_user_name}.key"'"' >> /home/${local.admin_username}/.bashrc
echo "}" >> /home/${local.admin_username}/.bashrc   
echo " " >> /home/${local.admin_username}/.bashrc   

echo "Installing and Configuring Demo Function"
echo "MULTIREGION_DEMO_INSTALL() {" >> /home/${local.admin_username}/.bashrc
echo "sudo yum install gcc -y" >> /home/${local.admin_username}/.bashrc
echo "sudo yum install gcc-c++ -y" >> /home/${local.admin_username}/.bashrc
echo "sudo yum install python36-devel -y" >> /home/${local.admin_username}/.bashrc
echo "sudo yum install libpq-devel -y" >> /home/${local.admin_username}/.bashrc

echo "sudo pip3 install sqlalchemy~=1.4" >> /home/${local.admin_username}/.bashrc
echo "sudo pip3 install sqlalchemy-cockroachdb" >> /home/${local.admin_username}/.bashrc
echo "sudo pip3 install psycopg2" >> /home/${local.admin_username}/.bashrc

echo "git clone https://github.com/nollenr/crdb-multi-region-demo.git" >> /home/${local.admin_username}/.bashrc
echo "echo 'DROP DATABASE IF EXISTS movr_demo;' > crdb-multi-region-demo/sql/db_configure.sql" >> /home/${local.admin_username}/.bashrc
echo "echo 'CREATE DATABASE movr_demo;' >> crdb-multi-region-demo/sql/db_configure.sql" >> /home/${local.admin_username}/.bashrc
echo "echo 'ALTER DATABASE movr_demo SET PRIMARY REGION = "\""${var.virtual_network_locations[0]}"\"";' >> crdb-multi-region-demo/sql/db_configure.sql" >> /home/${local.admin_username}/.bashrc
echo "echo 'ALTER DATABASE movr_demo ADD REGION "\""${element(var.virtual_network_locations,1)}"\"";' >> crdb-multi-region-demo/sql/db_configure.sql" >> /home/${local.admin_username}/.bashrc
echo "echo 'ALTER DATABASE movr_demo ADD REGION "\""${element(var.virtual_network_locations,2)}"\"";' >> crdb-multi-region-demo/sql/db_configure.sql" >> /home/${local.admin_username}/.bashrc
echo "echo 'ALTER DATABASE movr_demo SURVIVE REGION FAILURE;' >> crdb-multi-region-demo/sql/db_configure.sql" >> /home/${local.admin_username}/.bashrc
if [[ '${var.virtual_network_locations[0]}' == '${var.virtual_network_location}' ]]; then echo "cockroach-sql sql --url "\""postgres://${var.admin_user_name}@${azurerm_network_interface.haproxy[0].private_ip_address}:26257/defaultdb?sslmode=verify-full&sslrootcert=/home/${local.admin_username}/certs/ca.crt&sslcert=/home/${local.admin_username}/certs/client.${var.admin_user_name}.crt&sslkey=/home/${local.admin_username}/certs/client.${var.admin_user_name}.key"\"" --file crdb-multi-region-demo/sql/db_configure.sql" >> /home/${local.admin_username}/.bashrc; fi;
if [[ '${var.virtual_network_locations[0]}' == '${var.virtual_network_location}' ]]; then echo "cockroach-sql sql --url "\""postgres://${var.admin_user_name}@${azurerm_network_interface.haproxy[0].private_ip_address}:26257/defaultdb?sslmode=verify-full&sslrootcert=/home/${local.admin_username}/certs/ca.crt&sslcert=/home/${local.admin_username}/certs/client.${var.admin_user_name}.crt&sslkey=/home/${local.admin_username}/certs/client.${var.admin_user_name}.key"\"" --file crdb-multi-region-demo/sql/import.sql" >> /home/${local.admin_username}/.bashrc; fi;
echo "}" >> /home/${local.admin_username}/.bashrc
echo "# For demo usage.  The python code expects these environment variables to be set" >> /home/${local.admin_username}/.bashrc
echo "export DB_HOST="\""${azurerm_network_interface.haproxy[0].private_ip_address}"\"" " >> /home/${local.admin_username}/.bashrc
echo "export DB_USER="\""${var.admin_user_name}"\"" " >> /home/${local.admin_username}/.bashrc
echo "export DB_SSLCERT="\""/home/${local.admin_username}/certs/client.${var.admin_user_name}.crt"\"" " >> /home/${local.admin_username}/.bashrc
echo "export DB_SSLKEY="\""/home/${local.admin_username}/certs/client.${var.admin_user_name}.key"\"" " >> /home/${local.admin_username}/.bashrc
echo "export DB_SSLROOTCERT="\""/home/${local.admin_username}/certs/ca.crt"\"" " >> /home/${local.admin_username}/.bashrc
echo "export DB_SSLMODE="\""require"\"" " >> /home/${local.admin_username}/.bashrc
if [[ '${var.include_demo}' == 'yes' ]]; then echo "Installing Demo"; sleep 60; su ${local.admin_username} -lc 'MULTIREGION_DEMO_INSTALL'; fi;

    EOF
    )
}