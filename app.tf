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
    count                 = var.include_app == "yes" && var.create_ec2_instances == "yes" ? 1 : 0
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

    # os_disk {
    #     name      = "${var.owner}-${var.resource_name}-osdisk-app"
    #     caching   = "ReadWrite" # possible values: None, ReadOnly and ReadWrite
    #     storage_account_type = "Standard_LRS" # possible values: Standard_LRS, StandardSSD_LRS, Premium_LRS, Premium_SSD, StandardSSD_ZRS and Premium_ZRS
    # }
    os_disk {
        name      = "${var.owner}-${var.resource_name}-app-osdisk"
        caching   = "ReadWrite" # possible values: None, ReadOnly and ReadWrite
        storage_account_type = "Standard_LRS" # possible values: Standard_LRS, StandardSSD_LRS, Premium_LRS, Premium_SSD, StandardSSD_ZRS and Premium_ZRS
        disk_size_gb = var.app_disk_size
    }
    

    user_data = base64encode(<<EOF
#!/bin/bash -xe
echo "Shutting down and disabling firewalld -- SECURITY RISK!!"
systemctl stop firewalld
systemctl disable firewalld

if [ "${var.app_resize_homelv}" = "yes" ] 
then 
  echo "Attempting to resize /dev/mapper/rootvg-homelv with any space available on the physical volume"
  echo "Resize the Linux LVM"
  growpart /dev/sda 2
  echo "Capture the free space on the device in GB.  The awk command is capturing only the integer portion of the output"
  ds=`pvs -o name,free --units g --noheadings | awk '{printf "%dG\n", \$2}'`
  echo "Resizing the logical volume by $ds"
  lvresize -r -L +$ds /dev/mapper/rootvg-homelv
fi

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


echo " " >> /home/${local.admin_username}/.bashrc   
echo "Installing and Configuring Demo Function"
echo "PROMETHEUS_INSTALL(){" >> /home/${local.admin_username}/.bashrc   
echo "# Get the binary" >> /home/${local.admin_username}/.bashrc   
echo "sudo wget https://github.com/prometheus/prometheus/releases/download/v2.48.1/prometheus-2.48.1.linux-amd64.tar.gz -P /tmp" >> /home/${local.admin_username}/.bashrc   
echo "# create a group and user with no login privs" >> /home/${local.admin_username}/.bashrc   
echo "sudo groupadd --system prometheus" >> /home/${local.admin_username}/.bashrc   
echo "sudo useradd -s /sbin/nologin --system -g prometheus prometheus" >> /home/${local.admin_username}/.bashrc   
echo "# Create a directory for the binary" >> /home/${local.admin_username}/.bashrc   
echo "sudo mkdir /var/lib/prometheus" >> /home/${local.admin_username}/.bashrc   
echo "# Create configuration directories" >> /home/${local.admin_username}/.bashrc   
echo "for i in rules rules.d files_sd; do" >> /home/${local.admin_username}/.bashrc   
echo " sudo mkdir -p /etc/prometheus/${i};" >> /home/${local.admin_username}/.bashrc   
echo "done" >> /home/${local.admin_username}/.bashrc   
echo "# Extract Prometheus" >> /home/${local.admin_username}/.bashrc   
echo "sudo tar -xvf /tmp/prometheus-2.48.1.linux-amd64.tar.gz --directory /var/lib/prometheus" >> /home/${local.admin_username}/.bashrc   
echo "# Copy promtool and configuration files" >> /home/${local.admin_username}/.bashrc   
echo "sudo cp /var/lib/prometheus/prometheus-2.48.1.linux-amd64/prometheus /usr/local/bin/" >> /home/${local.admin_username}/.bashrc   
echo "sudo cp /var/lib/prometheus/prometheus-2.48.1.linux-amd64/promtool /usr/local/bin/" >> /home/${local.admin_username}/.bashrc   
echo "sudo cp -r /var/lib/prometheus/prometheus-2.48.1.linux-amd64/prometheus.yml /var/lib/prometheus/prometheus-2.48.1.linux-amd64/consoles/ /var/lib/prometheus/prometheus-2.48.1.linux-amd64/console_libraries/ /etc/prometheus/" >> /home/${local.admin_username}/.bashrc   
echo Create the systemd file
echo "echo 'echo "\""[Unit]"\"" > /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${local.admin_username}/.bashrc

echo "echo 'echo "\""Description=Prometheus"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "\""Documentation=https://prometheus.io/docs/introduction/overview/"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "\""Wants=network-online.target"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "\""After=network-online.target"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "\"" "\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "\""[Service]"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "\""Type=simple"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "\""User=prometheus"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "\""Group=prometheus"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo 'ExecReload=/bin/kill -HUP \$MAINPID' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo 'ExecStart=/usr/local/bin/prometheus \\' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo '  --config.file=/etc/prometheus/prometheus.yml \\' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo '  --storage.tsdb.path=/var/lib/prometheus \\' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo '  --web.console.templates=/etc/prometheus/consoles \\' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo '  --web.console.libraries=/etc/prometheus/console_libraries \\' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo '  --web.listen-address=0.0.0.0:9090 \\' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo '  --web.external-url=' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo ' ' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo 'SyslogIdentifier=prometheus' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo 'Restart=always' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo ' ' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo '[Install]' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo 'WantedBy=multi-user.target' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo "\""echo ' ' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${local.admin_username}/.bashrc

echo "# Create the prometheus.yml file" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "global:" > /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo -e "\""  scrape_interval:     5s"\"" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo -e "\""  evaluation_interval: 5s"\"" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "rule_files:" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo -e "\""  # - "first.rules"\"" " >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo -e "\""  # - "second.rules"\"" " >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "scrape_configs:" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo -e "\""  - job_name: prometheus"\"" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo -e "\""    static_configs:"\"" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo -e "\""    - targets: ['localhost:8000']"\"" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc
echo "echo 'echo "" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${local.admin_username}/.bashrc

echo "" >> /home/${local.admin_username}/.bashrc
echo "# Set Correct Directory and file permissions" >> /home/${local.admin_username}/.bashrc
echo "sudo chown -R prometheus:prometheus /etc/prometheus" >> /home/${local.admin_username}/.bashrc
echo "sudo chmod -R 775 /etc/prometheus/" >> /home/${local.admin_username}/.bashrc
echo "sudo chown -R prometheus:prometheus /var/lib/prometheus/" >> /home/${local.admin_username}/.bashrc

echo "" >> /home/${local.admin_username}/.bashrc 
echo "# Start the service" >> /home/${local.admin_username}/.bashrc
echo "sudo systemctl daemon-reload" >> /home/${local.admin_username}/.bashrc
echo "sudo systemctl start prometheus" >> /home/${local.admin_username}/.bashrc

echo "" >> /home/${local.admin_username}/.bashrc
echo "# Enable prometheus to start at boot" >> /home/${local.admin_username}/.bashrc
echo "sudo systemctl enable prometheus" >> /home/${local.admin_username}/.bashrc

echo "}" >> /home/${local.admin_username}/.bashrc

    EOF
    )
}