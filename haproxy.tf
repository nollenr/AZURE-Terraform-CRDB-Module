resource "azurerm_public_ip" "haproxy-ip" {
    # count                      = var.include_ha_proxy == "yes" ? 1 : 0
    count                        = 1
    name                         = "${var.owner}-${var.resource_name}-public-ip-haproxy"
    location                     = var.virtual_network_location
    resource_group_name          = local.resource_group_name
    allocation_method            = "Dynamic"
    sku                          = "Basic"
    tags                         = local.tags
}

resource "azurerm_network_interface" "haproxy" {
    # count                       = var.include_ha_proxy == "yes" ? 1 : 0
    count                     = 1
    name                      = "${var.owner}-${var.resource_name}-ni-haproxy"
    location                  = var.virtual_network_location
    resource_group_name       = local.resource_group_name
    tags                      = local.tags

    ip_configuration {
        name                          = "network-interface-haproxy-ip"
        subnet_id                     = azurerm_subnet.sn[0].id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.haproxy-ip[0].id
    }
}

resource "azurerm_linux_virtual_machine" "haproxy" {
    count                 = var.include_ha_proxy == "yes" && var.create_ec2_instances == "yes" ? 1 : 0
    name                  = "${var.owner}-${var.resource_name}-vm-haproxy"
    location              = var.virtual_network_location
    resource_group_name   = local.resource_group_name
    size                  = var.haproxy_vm_size
    tags                  = local.tags

    network_interface_ids = [azurerm_network_interface.haproxy[0].id]

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
    # do I assume this disk is deleted when the vm is deleted?  
    name      = "${var.owner}-${var.resource_name}-osdisk-haproxy"
    caching   = "ReadWrite" # possible values: None, ReadOnly and ReadWrite
    storage_account_type = "Standard_LRS" # possible values: Standard_LRS, StandardSSD_LRS, Premium_LRS, Premium_SSD, StandardSSD_ZRS and Premium_ZRS
  }

  user_data = base64encode(<<EOF
#!/bin/bash -xe
echo "Shutting down and disabling firewalld -- SECURITY RISK!!"
systemctl stop firewalld
systemctl disable firewalld
echo 'export CLUSTER_PRIVATE_IP_LIST="${local.ip_list}" ' >> /home/${local.admin_username}/.bashrc
export CLUSTER_PRIVATE_IP_LIST="${local.ip_list}"
echo "HAProxy Config and Install"
echo 'global' > /home/${local.admin_username}/haproxy.cfg
echo '  maxconn 4096' >> /home/${local.admin_username}/haproxy.cfg
echo '' >> /home/${local.admin_username}/haproxy.cfg
echo 'defaults' >> /home/${local.admin_username}/haproxy.cfg
echo '    mode                tcp' >> /home/${local.admin_username}/haproxy.cfg
echo '' >> /home/${local.admin_username}/haproxy.cfg
echo '    # Timeout values should be configured for your specific use.' >> /home/${local.admin_username}/haproxy.cfg
echo '    # See: https://cbonte.github.io/haproxy-dconv/1.8/configuration.html#4-timeout%20connect' >> /home/${local.admin_username}/haproxy.cfg
echo '' >> /home/${local.admin_username}/haproxy.cfg
echo '    # With the timeout connect 5 secs,' >> /home/${local.admin_username}/haproxy.cfg
echo '    # if the backend server is not responding, haproxy will make a total' >> /home/${local.admin_username}/haproxy.cfg
echo '    # of 3 connection attempts waiting 5s each time before giving up on the server,' >> /home/${local.admin_username}/haproxy.cfg
echo '    # for a total of 15 seconds.' >> /home/${local.admin_username}/haproxy.cfg
echo '    retries             2' >> /home/${local.admin_username}/haproxy.cfg
echo '    timeout connect     5s' >> /home/${local.admin_username}/haproxy.cfg
echo '' >> /home/${local.admin_username}/haproxy.cfg
echo '    # timeout client and server govern the maximum amount of time of TCP inactivity.' >> /home/${local.admin_username}/haproxy.cfg
echo '    # The server node may idle on a TCP connection either because it takes time to' >> /home/${local.admin_username}/haproxy.cfg
echo '    # execute a query before the first result set record is emitted, or in case of' >> /home/${local.admin_username}/haproxy.cfg
echo '    # some trouble on the server. So these timeout settings should be larger than the' >> /home/${local.admin_username}/haproxy.cfg
echo '    # time to execute the longest (most complex, under substantial concurrent workload)' >> /home/${local.admin_username}/haproxy.cfg
echo '    # query, yet not too large so truly failed connections are lingering too long' >> /home/${local.admin_username}/haproxy.cfg
echo '    # (resources associated with failed connections should be freed reasonably promptly).' >> /home/${local.admin_username}/haproxy.cfg
echo '    timeout client      10m' >> /home/${local.admin_username}/haproxy.cfg
echo '    timeout server      10m' >> /home/${local.admin_username}/haproxy.cfg
echo '' >> /home/${local.admin_username}/haproxy.cfg
echo '    # TCP keep-alive on client side. Server already enables them.' >> /home/${local.admin_username}/haproxy.cfg
echo '    option              clitcpka' >> /home/${local.admin_username}/haproxy.cfg
echo '' >> /home/${local.admin_username}/haproxy.cfg
echo 'listen psql' >> /home/${local.admin_username}/haproxy.cfg
echo '    bind :26257' >> /home/${local.admin_username}/haproxy.cfg
echo '    mode tcp' >> /home/${local.admin_username}/haproxy.cfg
echo '    balance roundrobin' >> /home/${local.admin_username}/haproxy.cfg
echo '    option httpchk GET /health?ready=1' >> /home/${local.admin_username}/haproxy.cfg
counter=1;for IP in $CLUSTER_PRIVATE_IP_LIST; do echo "    server cockroach$counter $IP:26257 check port 8080" >> /home/${local.admin_username}/haproxy.cfg; (( counter++ )); done
chown ${local.admin_username}:${local.admin_username} /home/${local.admin_username}/haproxy.cfg
echo "Installing HAProxy"; yum -y install haproxy
echo "Starting HAProxy as ${local.admin_username}"; su ${local.admin_username} -lc 'haproxy -f haproxy.cfg > haproxy.log 2>&1 &'
  EOF
  )
}