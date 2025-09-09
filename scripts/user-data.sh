#!/bin/bash

# Atualiza sistema e instala pacotes
apt update -y && apt install -y curl unzip jq nfs-common docker.io docker-compose

# Monta EFS
mkdir -p /mnt/efs/wordpress
mount -t nfs4 -o nfsvers=4.1 $EFS_DNS:/ /mnt/efs/wordpress
echo "$EFS_DNS:/ /mnt/efs/wordpress nfs4 defaults,_netdev 0 0" >> /etc/fstab
chown -R ubuntu:www-data /mnt/efs/wordpress
chmod 775 /mnt/efs/wordpress

# Busca credenciais do RDS
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id wordpress/RDS/credentials --query SecretString --output text --region us-east-1)
DB_USER=$(echo $SECRET_JSON | jq -r '.username')
DB_PASS=$(echo $SECRET_JSON | jq -r '.password')
DB_HOST=$(echo $SECRET_JSON | jq -r '.host')
DB_NAME=$(echo $SECRET_JSON | jq -r '.dbname')
EFS_DNS=$(echo $SECRET_JSON | jq -r '.efs_dns')

# Exporta variáveis de ambiente para Docker Compose
export WORDPRESS_DB_USER=$DB_USER
export WORDPRESS_DB_PASSWORD=$DB_PASS
export WORDPRESS_DB_HOST=$DB_HOST
export WORDPRESS_DB_NAME=$DB_NAME

# Docker Compose para WordPress
mkdir -p /home/ubuntu/wordpress-docker
cat <<EOL > /home/ubuntu/wordpress-docker/docker-compose.yml
services:
  wordpress:
    image: wordpress:latest
    container_name: wordpress
    ports:
      - "80:80"
    volumes:
      - /mnt/efs/wordpress:/var/www/html
    environment:
      WORDPRESS_DB_HOST: $DB_HOST
      WORDPRESS_DB_USER: $DB_USER
      WORDPRESS_DB_PASSWORD: $DB_PASS
      WORDPRESS_DB_NAME: $DB_NAME
    restart: always
EOL

cd /home/ubuntu/wordpress-docker
sudo -u ubuntu docker compose up -d --build --force-recreate