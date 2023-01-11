#!/bin/bash
# By Tra Viet
# Selinux and Firewall turn off before run this

# Set local time
timedatectl set-timezone Asia/Ho_Chi_Minh
timedatectl set-ntp 1

# Change hostname, Configure Hosts
sed -i '2d' /etc/hosts
sed -i '3 i 127.0.1.1       grafana.fptgroup.com' /etc/hosts
sed -i '4 i 10.10.100.162   grafana.fptgroup.com' /etc/hosts
hostnamectl set-hostname grafana

# Set Statics Ip
sed -i '5d' /etc/netplan/00-installer-config.yaml
sed -i '5 i \      addresses:' /etc/netplan/00-installer-config.yaml
sed -i '6 i \      - 10.10.100.162/24' /etc/netplan/00-installer-config.yaml
sed -i '7 i \      gateway4: 10.10.100.1' /etc/netplan/00-installer-config.yaml
sed -i '8 i \      nameservers:' /etc/netplan/00-installer-config.yaml
sed -i '9 i \        addresses:' /etc/netplan/00-installer-config.yaml
sed -i '10 i \        - 8.8.8.8' /etc/netplan/00-installer-config.yaml
sed -i '11 i \        - 10.10.100.100' /etc/netplan/00-installer-config.yaml
sed -i '12 i \        - 10.10.100.101' /etc/netplan/00-installer-config.yaml

sudo netplan apply

sleep 3

# Update && Upgrade Ubuntu
sudo apt-get update && sudo apt-get upgrade -y

# Install Tool for Ubuntu
sudo apt-get install -y apt-transport-https apache2 apache2-utils snmp 
sudo apt-get install -y net-tools network-manager software-properties-common wget curl gnupg2 openssl

sleep 3

# Grafana 
# Downloads Repository and Install Service
sudo wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install grafana -y

sleep 3

# Enable and Start Grafana Service
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

sleep 3 

# Configure Grafana for HTTPS
sed -i 's/;protocol = http/protocol = https/g' /etc/grafana/grafana.ini
sed -i 's/;http_addr =/http_addr = 0.0.0.0/g' /etc/grafana/grafana.ini
sed -i 's/;http_port = 3000/http_port = 3000/g' /etc/grafana/grafana.ini
sed -i 's/;cert_file =/cert_file = \/etc\/grafana\/cert\/grafana.crt/g' /etc/grafana/grafana.ini
sed -i 's/;cert_key =/cert_key = \/etc\/grafana\/cert\/grafana.key/g' /etc/grafana/grafana.ini

sleep 3

# Configure openssl for Grafana
sed -i '395 i [ grafana.fptgroup.com ]' /etc/ssl/openssl.cnf
sed -i '396 i subjectAltName = DNS:grafana.fptgroup.com' /etc/ssl/openssl.cnf

sleep 3
# Create Certificate for Grafana Web
openssl genrsa -aes128 2048 > /etc/ssl/private/grafana.key
openssl rsa -in /etc/ssl/private/grafana.key -out /etc/ssl/private/grafana.key
openssl req -utf8 -new -key /etc/ssl/private/grafana.key -out /etc/ssl/private/grafana.csr << EOF

VN
Ho Chi Minh
Ho Chi Minh
FPTGroup
grafana
grafana.fptgroup.com
grafana@fptgroup.com
grafanafptgroup
FPTGroup
EOF

# Export Key and Cert file
openssl x509 -in /etc/ssl/private/grafana.csr -out /etc/ssl/private/grafana.crt -req -signkey /etc/ssl/private/grafana.key -extfile /etc/ssl/openssl.cnf -extensions grafana.fptgroup.com -days 3650
chmod 600 /etc/ssl/private/grafana.key /etc/ssl/private/grafana.crt

sleep 3

# Create Cert file for Grafana
mkdir /etc/grafana/cert
sudo cp -a /etc/ssl/private/grafana.crt /etc/ssl/private/grafana.key /etc/grafana/cert
sudo chown grafana:grafana /etc/grafana/cert/grafana.key
sudo chown grafana:grafana /etc/grafana/cert/grafana.crt

systemctl restart grafana-server.service

sleep 3

# Create VirtualHost HTTPS GRAFANA
sudo cat << EOF > /etc/apache2/sites-available/grafana.fptgroup.com.conf 
<VirtualHost *:80> 
    ServerName grafana.fptgroup.com
    ServerAlias www.grafana.fptgroup.com
    Redirect permanent / https://grafana.fptgroup.com
</VirtualHost>

<VirtualHost *:443>

    ServerName grafana.fptgroup.com
    ServerAlias www.grafana.fptgroup.com
    ServerAdmin admin@grafana.fptgroup.com
    DocumentRoot /usr/share/grafana

    ErrorLog ${APACHE_LOG_DIR}/www.grafana.fptgroup.com_error.log
    CustomLog ${APACHE_LOG_DIR}/www.grafana.fptgroup.com_access.log combined

    SSLEngine on
    SSLCertificateFile /etc/grafana/cert/grafana.crt
    SSLCertificateKeyFile /etc/grafana/cert/grafana.key

   <Directory /usr/share/grafana>
      Options FollowSymlinks
      AllowOverride All
      Require all granted
   </Directory>

</VirtualHost>
EOF

sleep 3

# Turn off default Apache2
# Enable SSL and HTTPS for Grafana Web
sudo a2enmod ssl
sudo a2dissite 000-default.conf
sudo a2ensite grafana.fptgroup.com.conf
sudo apache2ctl configtest
sudo systemctl reload apache2

sleep 3

###___________________________________________________________________###

# Prometheus
# Downloads Prometheus Respo
wget https://github.com/prometheus/prometheus/releases/download/v2.41.0/prometheus-2.41.0.linux-amd64.tar.gz
tar -xvf prometheus-2.41.0.linux-amd64.tar.gz

# Add user Prometheus
groupadd --system prometheus
grep prometheus /etc/group
useradd -s /sbin/nologin -r -g prometheus prometheus

sleep 3

# Create Prometheus file and change owner 
sudo mkdir -p /var/lib/prometheus /etc/prometheus
mv prometheus-2.41.0.linux-amd64/promtool prometheus-2.41.0.linux-amd64/prometheus /usr/local/bin/
mv prometheus-2.41.0.linux-amd64/consoles prometheus-2.41.0.linux-amd64/console_libraries/ prometheus-2.41.0.linux-amd64/prometheus.yml /etc/prometheus/

chown -R prometheus:prometheus /etc/prometheus/*  /var/lib/prometheus/
chmod -R 775 /etc/prometheus/ /var/lib/prometheus/

sleep 3

# Configure Service
cat << EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus systemd service unit
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=prometheus
Group=prometheus
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/usr/local/bin/prometheus \
--config.file=/etc/prometheus/prometheus.yml \
--storage.tsdb.path=/var/lib/prometheus \
--web.console.templates=/etc/prometheus/consoles \
--web.console.libraries=/etc/prometheus/console_libraries \
--web.listen-address=0.0.0.0:9090 \
--storage.tsdb.retention.time=1y
SyslogIdentifier=prometheus
Restart=always
[Install]
WantedBy=multi-user.target
EOF

rm -rf prometheus-2.41.0.linux-amd64.tar.gz prometheus-2.41.0.linux-amd64

sleep 3

# Turn on Prometheus Service
systemctl daemon-reload
systemctl start prometheus
systemctl enable prometheus

sleep 3

# Prometheus Blackbox Exporter
# Download and Install Service
wget https://github.com/prometheus/blackbox_exporter/releases/download/v0.23.0/blackbox_exporter-0.23.0.linux-amd64.tar.gz
tar -xvf blackbox_exporter-0.23.0.linux-amd64.tar.gz
sudo mkdir -p /etc/blackbox
sudo useradd -rs /bin/false blackbox

# Move file Blackbox
mv blackbox_exporter-0.23.0.linux-amd64/blackbox.yml /etc/blackbox
chown -R blackbox:blackbox /etc/blackbox/*
mv blackbox_exporter-0.23.0.linux-amd64/blackbox_exporter /usr/local/bin
chown -R blackbox:blackbox /usr/local/bin/blackbox_exporter

rm -rf blackbox_exporter-0.23.0.linux-amd64.tar.gz blackbox_exporter-0.23.0.linux-amd64

sleep 3
# Configure Cervice
cat << EOF > /etc/systemd/system/blackbox.service
[Unit]
Description=Blackbox Exporter Service
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=blackbox
Group=blackbox
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/usr/local/bin/blackbox_exporter \
--config.file=/etc/blackbox/blackbox.yml \
--web.listen-address=":9115"
SyslogIdentifier=blackbox
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Enable Blackbox
systemctl daemon-reload
systemctl enable blackbox.service
systemctl start blackbox.service
systemctl restart prometheus.service

sleep 3

# Prometheus Node Exporter
# Download and Extract
wget https://github.com/prometheus/node_exporter/releases/download/v1.5.0/node_exporter-1.5.0.linux-amd64.tar.gz
tar -xvf node_exporter-1.5.0.linux-amd64.tar.gz

# Node Exporter move file and change owner
useradd -rs /bin/false node_exporter
mkdir -p /etc/node_exporter/cert
mv node_exporter-1.5.0.linux-amd64/node_exporter /usr/local/bin
chown -R node_exporter:node_exporter /usr/local/bin/node_exporter /etc/node_exporter/*
chown -R node_exporter:node_exporter /etc/node_exporter/*

# Configurage
 cat << EOF >/etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/usr/local/bin/node_exporter
SyslogIdentifier=node_exporter
Restart=always
[Install]
WantedBy=default.target
EOF

rm -rf node_exporter-1.5.0.linux-amd64.tar.gz node_exporter-1.5.0.linux-amd64

# Turn on Node Exporter
systemctl daemon-reload
systemctl start node_exporter
systemctl enable node_exporter
systemctl restart prometheus.service

sleep 3

# SSL Create for Prometheus
# Set up Certificatr and Export key
openssl genrsa -aes128 2048 > /etc/ssl/private/prometheus.key
openssl rsa -in /etc/ssl/private/prometheus.key -out /etc/ssl/private/prometheus.key
openssl req -utf8 -new -key /etc/ssl/private/prometheus.key -out /etc/ssl/private/prometheus.csr << EOF

VN
Ho Chi Minh
Ho Chi Minh
FPTGroup
prometheus
grafana.fptgroup.com
prometheus@fptgroup.com
prometheusfptgroup
FPTGroup
EOF

# Export Certificate and Move to Prometheus Cert File
# Change Owner
openssl x509 -in /etc/ssl/private/prometheus.csr -out /etc/ssl/private/prometheus.crt -req -signkey /etc/ssl/private/prometheus.key -extfile /etc/ssl/openssl.cnf -extensions grafana.fptgroup.com -days 3650
chmod 644 /etc/ssl/private/prometheus.key /etc/ssl/private/prometheus.crt
mkdir /etc/prometheus/cert
sudo cp -a /etc/ssl/private/prometheus.crt /etc/ssl/private/prometheus.key /etc/prometheus/cert
sudo chown prometheus:prometheus /etc/prometheus/cert/prometheus.key
sudo chown prometheus:prometheus /etc/prometheus/cert/prometheus.crt

sleep 3

#SSL Blackbox
# Set up Certificatr and Export key
openssl genrsa -aes128 2048 > /etc/ssl/private/blackbox.key
openssl rsa -in /etc/ssl/private/blackbox.key -out /etc/ssl/private/blackbox.key
openssl req -utf8 -new -key /etc/ssl/private/blackbox.key -out /etc/ssl/private/blackbox.csr << EOF

VN
Ho Chi Minh
Ho Chi Minh
FPTGroup
blackbox
grafana.fptgroup.com
blackbox@fptgroup.com
prometheusfptgroup
FPTGroup
EOF

# Export Certificate and Move to Blackbox Cert File
# Change Owner
openssl x509 -in /etc/ssl/private/blackbox.csr -out /etc/ssl/private/blackbox.crt -req -signkey /etc/ssl/private/blackbox.key -extfile /etc/ssl/openssl.cnf -extensions grafana.fptgroup.com -days 3650
chmod 644 /etc/ssl/private/blackbox.key /etc/ssl/private/blackbox.crt
mkdir /etc/blackbox/cert
sudo cp -a /etc/ssl/private/blackbox.crt /etc/ssl/private/blackbox.key /etc/blackbox/cert
sudo chown blackbox:blackbox /etc/blackbox/cert/blackbox.key
sudo chown blackbox:blackbox /etc/blackbox/cert/blackbox.crt


sleep 3

#SSL Node_Exporter
# Set up Certificatr and Export key
openssl genrsa -aes128 2048 > /etc/ssl/private/node_exporter.key
openssl rsa -in /etc/ssl/private/node_exporter.key -out /etc/ssl/private/node_exporter.key
openssl req -utf8 -new -key /etc/ssl/private/node_exporter.key -out /etc/ssl/private/node_exporter.csr << EOF

VN
Ho Chi Minh
Ho Chi Minh
FPTGroup
node_exporter
grafana.fptgroup.com
node_exporter@fptgroup.com
prometheusfptgroup
FPTGroup
EOF

# Export Certificate and Move to Blackbox Cert File
# Change Owner
openssl x509 -in /etc/ssl/private/node_exporter.csr -out /etc/ssl/private/node_exporter.crt -req -signkey /etc/ssl/private/node_exporter.key -extfile /etc/ssl/openssl.cnf -extensions grafana.fptgroup.com -days 3650
chmod 644 /etc/ssl/private/node_exporter.key /etc/ssl/private/node_exporter.crt
sudo cp -a /etc/ssl/private/node_exporter.crt /etc/ssl/private/node_exporter.key /etc/node_exporter/cert
sudo chown node_exporter:node_exporter /etc/node_exporter/cert/node_exporter.key
sudo chown node_exporter:node_exporter /etc/node_exporter/cert/node_exporter.crt

sleep 4

# Authen for Prometheus
mkdir -p /etc/apache2/htpasswd/
htpasswd -cB /etc/apache2/htpasswd/prometheus admin

cat << EOF > /etc/prometheus/web.yml
# create new
# specify your certificate
tls_server_config:
  cert_file: /etc/prometheus/cert/prometheus.crt
  key_file: /etc/prometheus/cert/prometheus.key

# specify username and password generated above
basic_auth_users:
EOF

sleep 3

sed -i 10's/$/ --web.config.file=\/etc\/prometheus\/web.yml &/' /etc/systemd/system/prometheus.service
sed -n '1p' /etc/apache2/htpasswd/prometheus >> /etc/prometheus/web.yml
sed -i 's/admin:/\        admin: /' /etc/prometheus/web.yml
promtool check web-config /etc/prometheus/web.yml

# Authen Blackbox HTTPS
htpasswd -cB /etc/apache2/htpasswd/blackbox admin

cat << EOF > /etc/blackbox/web.yml
# create new
# specify your certificate
tls_server_config:
  cert_file: /etc/blackbox/cert/blackbox.crt
  key_file: /etc/blackbox/cert/blackbox.key

# specify username and password generated above
basic_auth_users:
EOF

sed -i 10's/$/ --web.config.file=\/etc\/blackbox\/web.yml &/' /etc/systemd/system/blackbox.service
sed -n '1p' /etc/apache2/htpasswd/blackbox >> /etc/blackbox/web.yml
sed -i 's/admin:/\        admin: /' /etc/blackbox/web.yml
promtool check web-config /etc/blackbox/web.yml

# Authen Node_Exploxer
htpasswd -cB /etc/apache2/htpasswd/node_exporter admin

cat << EOF > /etc/node_exporter/web.yml
# create new
# specify your certificate
tls_server_config:
  cert_file: /etc/node_exporter/cert/node_exporter.crt
  key_file: /etc/node_exporter/cert/node_exporter.key

# specify username and password generated above
basic_auth_users:
EOF

sed -i 10's/$/ --web.config.file=\/etc\/node_exporter\/web.yml &/' /etc/systemd/system/node_exporter.service
sed -n '1p' /etc/apache2/htpasswd/node_exporter >> /etc/node_exporter/web.yml
sed -i 's/admin:/\        admin: /' /etc/node_exporter/web.yml
promtool check web-config /etc/node_exporter/web.yml

sleep 3

# Restart Promethues/Blackbox/Node Exporter Service
sudo systemctl daemon-reload
sudo systemctl restart prometheus.service
sudo systemctl restart blackbox.service
sudo systemctl restart node_exporter.service

# Create Rule Prometheus
mkdir -p /etc/prometheus/rules
cat << EOF >/etc/prometheus/rules/blackbox.yml

groups:
  - name: Blackbox rules
    rules:
      - alert: BlackboxSslCertificateWillExpireSoon
        expr: probe_ssl_earliest_cert_expiry - time() < 86400 * 7
        for: 5m
        labels:
          severity: warning
        annotations:
          description: "TLS certificate will expire in {{ \$value | humanizeDuration }} (instance {{ \$labels.instance }})"

      - alert: EndpointDown
        expr: probe_success == 0
        for: 10m
        labels:
          severity: "critical"
        annotations:
          summary: "Endpoint {{ \$labels.instance }} down"

EOF
# Rule Set Linux
cat << EOF >/etc/prometheus/rules/nodeexporter.yml
groups:
  - name: Linux Server
    rules:
      - alert: Server Linux Down
        expr: up{job="node_exporter"} == 0
        for: 10s
        labels:
          severity: "Critical"
        annotations:
          Summary: 'Server "{{ \$labels.instance }}" down.'
EOF

# change Alertmanager
sed -i 's/          # - alertmanager:9093/            - localhost:9093/g' /etc/prometheus/prometheus.yml
# Add Rule to Prometheus Configure Service
sed -i '18i \    - "/etc/prometheus/rules/nodeexporter.yml"\n    - "/etc/prometheus/rules/blackbox.yml"' /etc/prometheus/prometheus.yml
# Add Authen Confirm for Prometheus
sed -i "27i \    scheme: https\n    tls_config:\n      cert_file: \/etc\/prometheus\/cert\/prometheus.crt\n      key_file: \/etc\/prometheus\/cert\/prometheus.key\n      insecure_skip_verify: true\n    basic_auth:\n      username: 'admin'\n      password: 'fptgroup'" /etc/prometheus/prometheus.yml
# Change Configure of Blackbox Monitoring SSL
sed -i '4i \    timeout: 5s\n    http:\n      method: GET\n      fail_if_ssl: false\n      fail_if_not_ssl: true\n      valid_http_versions: ["HTTP\/1.1", "HTTP\/2.0"]\n      valid_status_codes: [200]\n      no_follow_redirects: false\n      preferred_ip_protocol: "ip4"' /etc/blackbox/blackbox.yml

# Add Node Monitoring and Blackbox Monitoring SSL
tee -a /etc/prometheus/prometheus.yml <<EOF
# Blackbox SSL
  - job_name: 'blackbox'
    scheme: https
    tls_config:
      cert_file: /etc/blackbox/cert/blackbox.crt
      key_file: /etc/blackbox/cert/blackbox.key
      insecure_skip_verify: true
    basic_auth:
      username: 'admin'
      password: 'fptgroup'
    metrics_path: /probe
    params:
     module: [http_2xx] # Look for a HTTP 200 response.
    static_configs:
    - targets:
       - https://jetking.fpt.edu.vn/
       - https://facebook.com
       - https://google.com
       - https://fptgroup2.com
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: 127.0.0.1:9115


# Node Exporter
  - job_name: 'node_exporter'
    scheme: https
    tls_config:
      cert_file: /etc/node_exporter/cert/node_exporter.crt
      key_file: /etc/node_exporter/cert/node_exporter.key
      insecure_skip_verify: true
    basic_auth:
      username: 'admin'
      password: 'fptgroup'
    scrape_interval: 5s
    static_configs:
    - targets:
      - 10.10.100.162:9100
      - 10.10.100.164:9100
EOF

sleep 3

# Grafana Plugin intall
#grafana-cli plugins list-remote (show Plugins Grafana)
grafana-cli plugins install alexanderzobnin-zabbix-app
grafana-cli plugins install grafana-clock-panel
grafana-cli plugins install grafana-worldmap-panel
grafana-cli plugins install jasonlashua-prtg-datasource
grafana-cli plugins install grafana-image-renderer
grafana-cli plugins install camptocamp-prometheus-alertmanager-datasource
grafana-cli plugins install grafana-piechart-panel
grafana-cli plugins update-all

sudo systemctl restart grafana-server.service

sleep 3

sudo systemctl daemon-reload
sudo systemctl restart prometheus.service
sudo systemctl restart blackbox.service
sudo systemctl restart node_exporter.service

sleep 3

sudo ufw allow proto tcp from any to any port 80,443,3000,9090,9100,9115,9093,22,161
sudo ufw allow proto tcp from 10.10.100.161 to any port 10050,10051
sudo ufw allow proto tcp from 10.10.100.164 to any port 5665
sudo ufw enable

sudo passwd user <<EOF
Fpt@@123
Fpt@@123
EOF

rm -rf grafana
