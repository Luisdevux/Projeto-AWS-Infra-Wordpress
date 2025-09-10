#!/bin/bash

# Script de automação com user-data para configurar uma instância EC2 com Wordpress

# Atualiza pacotes e sistema
apt update -y
apt upgrade -y
apt install -y curl gnupg lsb-release software-properties-common unzip jq nfs-common

# Instala AWS CLI via curl
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

# Instala Docker e Docker Compose
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Habilita e inicia Docker
systemctl enable docker
systemctl start docker

# Adiciona usuário ubuntu ao grupo docker
usermod -aG docker ubuntu

# Busca credenciais do Secrets Manager para preencher (RDS + EFS)
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id wordpress/RDS/credentials \
    --query SecretString \
    --output text \
    --region us-east-1)

DB_USER=$(echo $SECRET_JSON | jq -r '.username')
DB_PASS=$(echo $SECRET_JSON | jq -r '.password')
DB_HOST=$(echo $SECRET_JSON | jq -r '.host')
DB_NAME=$(echo $SECRET_JSON | jq -r '.dbname')
EFS_DNS=$(echo $SECRET_JSON | jq -r '.efs_dns')

export WORDPRESS_DB_USER=$DB_USER
export WORDPRESS_DB_PASSWORD=$DB_PASS
export WORDPRESS_DB_HOST=$DB_HOST
export WORDPRESS_DB_NAME=$DB_NAME

# Monta e configura EFS
mkdir -p /mnt/efs/wordpress
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 $EFS_DNS:/ /mnt/efs/wordpress

# Montagem automática no reboot
echo "$EFS_DNS:/ /mnt/efs/wordpress nfs4 defaults,_netdev 0 0" >> /etc/fstab

# Ajusta permissões para o www-data do wordpress permitir upload de mídias
chown -R 33:33 /mnt/efs/wordpress

# Permite leitura/escrita para grupo
chmod -R 775 /mnt/efs/wordpress

# Adiciona o usuário ubuntu ao mesmo grupo (33 = www-data)
usermod -aG 33 ubuntu

# Espera banco ficar disponível para conexão
for i in {1..10}; do
    nc -zv $DB_HOST 3306 && break
    echo "Aguardando banco de dados $DB_HOST..."
    sleep 5
done

# Configura Docker Compose WordPress
mkdir -p /home/ubuntu/wordpress-docker
chown -R ubuntu:ubuntu /home/ubuntu/wordpress-docker

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
            WORDPRESS_DB_HOST: $WORDPRESS_DB_HOST
            WORDPRESS_DB_USER: $WORDPRESS_DB_USER
            WORDPRESS_DB_PASSWORD: $WORDPRESS_DB_PASSWORD
            WORDPRESS_DB_NAME: $WORDPRESS_DB_NAME
        restart: always
EOL

cd /home/ubuntu/wordpress-docker
sudo -u ubuntu docker compose up -d --build --force-recreate