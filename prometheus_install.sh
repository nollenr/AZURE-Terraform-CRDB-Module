
echo " " >> /home/${admin_username}/.bashrc   
echo "Installing and Configuring Demo Function"
echo "PROMETHEUS_INSTALL(){" >> /home/${admin_username}/.bashrc   
echo "# Get the binary" >> /home/${admin_username}/.bashrc   
echo "sudo wget https://github.com/prometheus/prometheus/releases/download/v2.48.1/prometheus-2.48.1.linux-amd64.tar.gz -P /tmp" >> /home/${admin_username}/.bashrc   
echo "# create a group and user with no login privs" >> /home/${admin_username}/.bashrc   
echo "sudo groupadd --system prometheus" >> /home/${admin_username}/.bashrc   
echo "sudo useradd -s /sbin/nologin --system -g prometheus prometheus" >> /home/${admin_username}/.bashrc   
echo "# Create a directory for the binary" >> /home/${admin_username}/.bashrc   
echo "sudo mkdir /var/lib/prometheus" >> /home/${admin_username}/.bashrc   
echo "# Create configuration directories" >> /home/${admin_username}/.bashrc   
echo "for i in rules rules.d files_sd; do" >> /home/${admin_username}/.bashrc   
echo " sudo mkdir -p /etc/prometheus/${i};" >> /home/${admin_username}/.bashrc   
echo "done" >> /home/${admin_username}/.bashrc   
echo "# Extract Prometheus" >> /home/${admin_username}/.bashrc   
echo "sudo tar -xvf /tmp/prometheus-2.48.1.linux-amd64.tar.gz --directory /var/lib/prometheus" >> /home/${admin_username}/.bashrc   
echo "# Copy promtool and configuration files" >> /home/${admin_username}/.bashrc   
echo "sudo cp /var/lib/prometheus/prometheus-2.48.1.linux-amd64/prometheus /usr/local/bin/" >> /home/${admin_username}/.bashrc   
echo "sudo cp /var/lib/prometheus/prometheus-2.48.1.linux-amd64/promtool /usr/local/bin/" >> /home/${admin_username}/.bashrc   
echo "sudo cp -r /var/lib/prometheus/prometheus-2.48.1.linux-amd64/prometheus.yml /var/lib/prometheus/prometheus-2.48.1.linux-amd64/consoles/ /var/lib/prometheus/prometheus-2.48.1.linux-amd64/console_libraries/ /etc/prometheus/" >> /home/${admin_username}/.bashrc   
echo Create the systemd file
echo "echo 'echo "\""[Unit]"\"" > /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${admin_username}/.bashrc

echo "echo 'echo "\""Description=Prometheus"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "\""Documentation=https://prometheus.io/docs/introduction/overview/"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "\""Wants=network-online.target"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "\""After=network-online.target"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "\"" "\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "\""[Service]"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "\""Type=simple"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "\""User=prometheus"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "\""Group=prometheus"\"" >> /etc/systemd/system/prometheus.service' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo 'ExecReload=/bin/kill -HUP \$MAINPID' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo 'ExecStart=/usr/local/bin/prometheus \\' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo '  --config.file=/etc/prometheus/prometheus.yml \\' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo '  --storage.tsdb.path=/var/lib/prometheus \\' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo '  --web.console.templates=/etc/prometheus/consoles \\' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo '  --web.console.libraries=/etc/prometheus/console_libraries \\' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo '  --web.listen-address=0.0.0.0:9090 \\' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo '  --web.external-url=' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo ' ' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo 'SyslogIdentifier=prometheus' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo 'Restart=always' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo ' ' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo '[Install]' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo 'WantedBy=multi-user.target' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo "\""echo ' ' >> /etc/systemd/system/prometheus.service"\"" | sudo -s" >> /home/${admin_username}/.bashrc

echo "# Create the prometheus.yml file" >> /home/${admin_username}/.bashrc
echo "echo 'echo "global:" > /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo -e "\""  scrape_interval:     5s"\"" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo -e "\""  evaluation_interval: 5s"\"" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "rule_files:" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo -e "\""  # - "first.rules"\"" " >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo -e "\""  # - "second.rules"\"" " >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "scrape_configs:" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo -e "\""  - job_name: prometheus"\"" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo -e "\""    static_configs:"\"" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo -e "\""    - targets: ['localhost:8000']"\"" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc
echo "echo 'echo "" >> /etc/prometheus/prometheus.yml' | sudo -s" >> /home/${admin_username}/.bashrc

echo "" >> /home/${admin_username}/.bashrc
echo "# Set Correct Directory and file permissions" >> /home/${admin_username}/.bashrc
echo "sudo chown -R prometheus:prometheus /etc/prometheus" >> /home/${admin_username}/.bashrc
echo "sudo chmod -R 775 /etc/prometheus/" >> /home/${admin_username}/.bashrc
echo "sudo chown -R prometheus:prometheus /var/lib/prometheus/" >> /home/${admin_username}/.bashrc

echo "" >> /home/${admin_username}/.bashrc 
echo "# Start the service" >> /home/${admin_username}/.bashrc
echo "sudo systemctl daemon-reload" >> /home/${admin_username}/.bashrc
echo "sudo systemctl start prometheus" >> /home/${admin_username}/.bashrc

echo "" >> /home/${admin_username}/.bashrc
echo "# Enable prometheus to start at boot" >> /home/${admin_username}/.bashrc
echo "sudo systemctl enable prometheus" >> /home/${admin_username}/.bashrc

echo "}" >> /home/${admin_username}/.bashrc
