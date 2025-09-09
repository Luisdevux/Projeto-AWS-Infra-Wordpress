# Projeto AWS EC2 - WordPress com Docker e EFS

![AWS](https://img.shields.io/badge/AWS-EC2-orange)
![AWS](https://img.shields.io/badge/AWS-RDS-blue)
![AWS](https://img.shields.io/badge/AWS-EFS-green)
![Shell Script](https://img.shields.io/badge/Shell-Script-orange)
![Docker](https://img.shields.io/badge/Docker-Container-blue)
![WordPress](https://img.shields.io/badge/WordPress-CMS-green)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

Este projeto demonstra a automação do deploy de um **WordPress** em uma instância EC2 da AWS utilizando Docker e EFS, garantindo persistência de arquivos de mídia e integração com banco de dados RDS. Todo o processo é automatizado via **user-data**, incluindo instalação de Docker, configuração do WordPress e montagem do EFS.

O objetivo é entregar uma solução **pronta para produção**, com escalabilidade futura, backup de arquivos e facilidade de manutenção.

---

## 🛠 Tecnologias Utilizadas

- **Amazon EC2** — Instância virtual Ubuntu Server;
- **Amazon EFS** — Sistema de arquivos compartilhado para persistência de mídias;
- **Amazon RDS (MySQL)** — Banco de dados para WordPress;
- **Docker & Docker Compose** — Containers para WordPress;
- **Shell Script** — Automação via user-data;
- **jq** — Processamento de JSON para buscar credenciais no AWS Secrets Manager;
- **NFS Utils** — Montagem do EFS na instância;
- **AWS CLI** — Para integração com Secrets Manager e outras ferramentas.

---

## ✅ Pré-requisitos

Antes de executar este projeto:

- Ter uma **conta AWS** com permissões para criar EC2, EFS, RDS e IAM;
- Um secret no Secrets Manager contendo as credenciais do RDS e DNS do EFS;
- Rede com VPC, Subnets e Security Groups configurados. Caso não possua, a sessão mais abaixo terá informações.

---

## 🧱 Arquitetura da Solução

A solução foi construída para ser executada automaticamente no primeiro boot da instância EC2. O fluxo principal é:

1. Instância EC2 é criada com imagem `Ubuntu` e `user-data` configurado.
2. Durante o boot, o script `user-data`:
   - Atualiza o sistema e instala dependências (Docker, Docker Compose, NFS, AWS CLI, jq).
   - Monta o EFS dinamicamente usando o DNS obtido via Secrets Manager.
   - Ajusta permissões de www-data para uploads de mídias.
   - Recupera as credenciais do RDS e configura variáveis de ambiente.
   - Configura o Docker Compose para rodar WordPress com volume para o EFS.
3. Docker cria e inicia o container do WordPress, conectado ao banco e com armazenamento persistente, onde:
   - Porta `80` exposta.
   - Volume `/mnt/efs/wordpress:/var/www/html`.
   - Banco de dados conectado via variáveis de ambiente do `Secrets Manager`.
4. O WordPress pode receber uploads e persistir arquivos no EFS.
5. Permissões e grupo do usuário Ubuntu são ajustados para interagir com os arquivos do container.

---

## 🌐 VPC e Subnets

A infraestrutura foi provisionada em uma VPC customizada na região `us-east-1`.

Foram criadas subnets públicas e privadas distribuídas em duas zonas de disponibilidade (AZs) para garantir alta disponibilidade e redundância.

### 📦 Estrutura da VPC

- **VPC CIDR:** `10.0.0.0/16`
- **Subnets públicas:** permitem acesso direto à internet via Internet Gateway (IGW). Hospedam o Application Load Balancer (ALB) e o NAT Gateway.
- **Subnets privadas:** não têm acesso direto da internet. Hospedam os recursos EC2 (WordPress), RDS (MySQL) e EFS.
- **NAT Gateway:** fica em subnet pública e fornece saída para a internet aos recursos em subnets privadas.
### 🗺️ Tabela de Subnets

| Nome da Subnet | Zona de Disponibilidade | Faixa de IP (CIDR) | Tipo | Recursos associados |
| :--- | :--- | :--- | :--- | :--- |
| Public Subnet 1 | us-east-1a | `10.0.1.0/24` | Pública | ALB, NAT Gateway |
| Public Subnet 2 | us-east-1b | `10.0.3.0/24` | Pública | ALB, NAT Gateway |
| Private Subnet 1 | us-east-1a | `10.0.2.0/24` | Privada | EC2, RDS, EFS |
| Private Subnet 2 | us-east-1b | `10.0.4.0/24` | Privada | EC2, RDS, EFS |

### 🔗 Comunicação entre Subnets

- ALB recebe tráfego HTTP da internet nas subnets públicas.
- EC2 roda em subnets privadas e recebe tráfego somente do ALB.
- RDS e EFS ficam em subnets privadas, acessíveis apenas pelas EC2.
- NAT Gateway (em subnets públicas) garante que instâncias privadas acessem a internet sem ficarem expostas.

---

## 🔐 Grupos de Segurança (Security Group)

| Nome / Recurso       | Tipo    | Protocolo | Porta | Origem / Destino   | Descrição                                      |
| -------------------- | ------- | --------- | ----- | ------------------ | ---------------------------------------------- |
| **SG-ALB (Load Balancer)** | Entrada | TCP | 80    | 0.0.0.0/0          | Permite acesso HTTP público
|                      | Saída   | All       | All   | 0.0.0.0/0          | Permite encaminhar tráfego para targets
| **SG-WordPress (EC2/WordPress)** | Entrada | TCP       | 80    | SG-ALB          | Permite acesso HTTP apenas do ALB      |
|                      | Saída   | All       | All   | 0.0.0.0/0          | Permite comunicação externa                    |
| **SG-RDS (Database RDS)** | Entrada | TCP       | 3306  | SG-WordPress   | Permite apenas que a instância EC2 acesse o DB |
|                      | Saída   | All       | All   | 0.0.0.0/0          | Comunicação padrão de saída                    |
| **SG-EFS (File System EFS)** | Entrada | TCP       | 2049  | SG-WordPress   | Permite apenas que a instância EC2 monte o EFS |
|                      | Saída   | All       | All   | 0.0.0.0/0          | Comunicação padrão de saída                    |


> ⚠️ Recomendado restringir e manter toda a infraestrututra privada para maior segurança, tendo acesso a aplicação somente a partir do Load Balancer.

---

## 🌐 Fluxo de Tráfego e Application Load Balancer (ALB)

O tráfego externo é direcionado para a aplicação através do **Application Load Balancer (ALB)**, que fica em subnets públicas. O ALB distribui o tráfego HTTP para as instâncias EC2 privadas onde o WordPress está rodando.

-   **Ingressos:** Usuários acessam via internet → ALB (subnets públicas).
-   **Destino:** ALB encaminha tráfego apenas para EC2 (subnets privadas).
-   **Segurança:** Apenas o SG do ALB permite acesso público; EC2 só aceita tráfego do SG do ALB.

Esse modelo mantém a aplicação privada e segura, permitindo acesso externo apenas pelo ALB.

---

## 📈 Escalabilidade e Segurança (Auto Scaling e IAM)

-   O ambiente conta com um **Auto Scaling Group (ASG)** configurado com múltiplas AZs (`us-east-1a` e `us-east-1b`).
-   As instâncias EC2 que rodam WordPress são criadas automaticamente pelo ASG, conectadas ao ALB e distribuídas entre as subnets privadas.
-   **Health Checks** do ALB monitoram o status das instâncias e só direcionam tráfego para instâncias saudáveis.

### IAM (Identity and Access Management)

-   Cada instância EC2 possui um **IAM Role** com permissões mínimas necessárias para acessar o Secrets Manager.
-   As credenciais do RDS e o DNS do EFS são obtidos dinamicamente via IAM, garantindo segurança e evitando o armazenamento de senhas no script.


---

## ⚙️ Configuração do Template das Instâncias EC2

- **AMI:** Ubuntu Server 24.04 LTS.
- **Tipo de instância:** t3.micro (Free Tier compatível).
- **Armazenamento:** 8 GB SSD.
- **Subnet:** Privada.
- **Elastic IP:** Associado manualmente para IP fixo.
- **IAM:** Política de acesso para as credenciais armazenadas no Secrets Manager.
- **User Data:** Script de inicialização que instala Docker, configura EFS, busca credenciais e sobe WordPress.

---

## 📝 Script de Inicialização (User Data)

O script `user-data` automatiza:

- Instalação de pacotes essenciais (Docker, Docker Compose, AWS CLI, jq, NFS);
- Busca de credenciais no Secrets Manager;
- Montagem do EFS em `/mnt/efs/wordpress`;
- Ajuste de permissões para `www-data` e `ubuntu`;
- Espera o banco de dados ficar disponível;
- Criação e execução do Docker Compose para WordPress.

### Trecho do Script:

```bash
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
```

---

## ⚠️ Algumas Dificuldades Encontradas e Soluções

Durante a implementação do projeto, algumas dificuldades técnicas foram identificadas. Abaixo estão os principais problemas e como foram solucionados:

### 1. 🚫 Falha ao resolver DNS do EFS

-   **Problema:** A instância EC2 não conseguia resolver o DNS do Amazon EFS.
-   **Causa:** A opção “Nomes de host DNS” estava desabilitada na VPC, impedindo a resolução de nomes internos.
-   **Solução:** Foi habilitado a "Resolução de DNS" e "Nomes de host DNS" nas configurações da VPC. Após isso, o EFS pôde ser montado corretamente.

### 2. 🐢 Timeout/erro na conexão com o banco RDS

-   **Problema:** O script `user-data` falhava ao conectar no RDS.
-   **Causa:** O RDS foi criado sem definir a AZ de preferência e acabou provisionado na `us-east-1b`, enquanto a infraestrutura (EC2 + subnets privadas) estava na `us-east-1a`. Isso impedia a comunicação entre a aplicação e o banco.
-   **Solução:** Foi recriado o banco RDS, fixando a mesma Availability Zone da infraestrutura (`us-east-1a`).

### 3. 🔒 Permissão de escrita em uploads do WordPress

-   **Problema:** O WordPress não conseguia criar pastas em `wp-content/uploads`, para armazenar mídias.
-   **Causa:** O diretório montado no EFS não tinha permissões para o usuário do container (`www-data`, UID 33).
-   **Solução:** No `user-data`, foram configuradas permissões adequadas com os comandos `chown -R 33:33` e `chmod -R 775` e adicionamos o usuário `ubuntu` ao grupo 33. Assim, os uploads passaram a funcionar.

### 4. 🏥 Health Check do ALB não identificava instâncias como saudáveis

-   **Problema:** O ALB marcava as instâncias como `unhealthy`, mesmo com o WordPress ativo.
-   **Causa:** O range de respostas HTTP configurado no health check não incluía todos os códigos válidos retornados pelo WordPress (ex: redirecionamentos 3xx).
-   **Solução:** Foi ajustado o range de códigos de sucesso para `200-399` no Health Check do Target Group do ALB, garantindo que as instâncias fossem consideradas saudáveis corretamente.

---

> ### Este projeto está licenciado sob a [Licença MIT](./LICENSE).