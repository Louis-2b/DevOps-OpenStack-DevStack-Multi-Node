# Déploiement OpenStack avec DevStack

Ce guide documente les étapes complètes pour préparer un serveur, installer et déployer OpenStack en utilisant **DevStack** sur un **OS DEBIAN 12, 13**.

## Prérequis généraux

### Ressources : Recommandations minimales par nœud :
Tout d'abord, configurez une machine virtuelle de votre choix avec au moins **8 Go de RAM** et **4 vCPU** **100 Go d'espace disque**. Assurez-vous qu'elle est à jour. Installez **Git** et tout autre outil de développement utile.

---

## 1. Préparation du système (A faire sur les 2 machines 1 contrôleur + 1 compute)

```bash
sudo apt update -y && apt upgrade -y
```

### Créer l'utilisateur stack

```bash
sudo useradd -s /bin/bash -d /opt/stack -m stack
echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack
```

### Informations système

```bash
lsb_release -a
id
nproc
free -mh
```

### Vérification KVM

```bash
sudo apt install cpu-checker -y
sudo kvm-ok
```
Pour processeur AMD

```bash
sudo modprobe kvm-amd
echo 'options kvm-amd nested=1' | sudo tee -a /etc/modprobe.d/kvm-amd.conf
sudo modprobe -r kvm-amd
sudo modprobe kvm-amd
```
Pour processeur Intel

```bash
sudo modprobe kvm-intel
echo 'options kvm-intel nested=1' | sudo tee -a /etc/modprobe.d/kvm-intel.conf
sudo modprobe -r kvm-intel
sudo modprobe kvm-intel
```

Vérifier :

```bash
cat /sys/module/kvm_intel/parameters/nested
```

## 2. Réseautage

### Afficher les interfaces réseau

```bash
ip a
```

Exemple de configuration :

```bash
sudo nano /etc/network/interfaces

# Interface physique pour le management (ens33)
allow-hotplug ens33
iface ens33 inet static
    address 192.168.1.121/24
    gateway 192.168.1.254
    dns-nameservers 8.8.8.8 8.8.4.4

# Interface physique pour le bridge externe (ens34) - pas d'IP
allow-hotplug ens34
iface ens34 inet manual
    up ip link set dev $IFACE up
    down ip link set dev $IFACE down    
```

Redémarrer :

```bash
# Appliquer la nouvelle configuration
sudo systemctl restart networking
```

## 3. Stockage (A faire sur la machine contrôleur)

### Liste des disques

```bash
lsblk
```

### Configuration LVM pour Cinder 

```bash
sudo pvcreate /dev/sdb
sudo vgcreate cinder-volumes /dev/sdb
sudo vgs
```

## 4. SSH (A faire sur la machine contrôleur)
###  Génération de la paire de clés SSH (Ed25519 recommandé pour la sécurité)

```bash
ssh-keygen -t ed25519 -C "devstack" -f ~/.ssh/devstack
```

### Copier la clé publique vers la machine compute

```bash
cat ~/.ssh/devstack.pub | ssh compute@192.168.1.41 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# Tester la connexion
ssh -i ~/.ssh/devstack compute@192.168.1.41
```

### Téléchargement de DevStack sur les 2 machines (1 contrôleur + 1 compute)

Avant de lancer DevStack, assure toi d'avoir :
```bash
sudo apt install -y git python3-pip lvm2 thin-provisioning-tools python3-venv libpq-dev python3-dev
# ou :
sudo apt install -y git python3-pip python3-dev python3-venv libffi-dev gcc libssl-dev bridge-utils
```

```bash
# Se connecter en tant que stack
sudo su - stack

# Cloner DevStack
git clone https://opendev.org/openstack/devstack
cd devstack/tools
sudo ./create-stack-user.sh
cd ../..
sudo mv devstack /opt/stack
sudo chown -R stack.stack /opt/stack/devstack

# Vérifier la connectivité réseau
ping -c 3 192.168.1.121  # Depuis compute vers contrôleur
```


# Étapes d’installation

## 1. Configuration du nœud contrôleur
Le nœud contrôleur exécute tous les services OpenStack.

### Créer le fichier de configuration local.conf
Modifiez votre /opt/stack/devstack/local.conf pour qu'il ressemble à :

```bash
nano local.conf


[[local|localrc]]

# +++++++++++++++++++++
# CONFIGURATION RESEAU
# +++++++++++++++++++++
# Adresse IP du nœud contrôleur (ton IP LAN)
HOST_IP=192.168.1.121
SERVICE_HOST=192.168.1.121

# Plage réseau interne (pour les instances)
FIXED_RANGE=10.0.1.0/24
FIXED_NETWORK_SIZE=256

# Plage d’adresses IP flottantes (doit appartenir au même réseau que HOST_IP)
FLOATING_RANGE=192.168.1.122/27
Q_FLOATING_ALLOCATION_POOL=start=192.168.1.123,end=192.168.1.130

# interface reliée au LAN externe (pas d’IP assignée directement)
PUBLIC_INTERFACE=ens34
FLAT_INTERFACE=$PUBLIC_INTERFACE

# Serveurs DNS pour les instances
PUBLIC_NETWORK_GATEWAY=192.168.1.1
DNS_SERVERS=8.8.8.8,8.8.4.4

# ++++++++++++++++++++++++++++
# AUTHENTIFICATION & SECURITE
# ++++++++++++++++++++++++++++
ADMIN_PASSWORD=password
DATABASE_PASSWORD=password
RABBIT_PASSWORD=password
SERVICE_PASSWORD=password
SERVICE_TOKEN=password

# ++++++++++++++++++++
# Keystone (Identity)
# ++++++++++++++++++++
KEYSTONE_TONE_FORMAT=fernet
KEYSTONE_CATALOG_BACKEND=sql

# +++++++++++++++++++++++++
# CONFIGURATION MULTI-NOEUD
# +++++++++++++++++++++++++
MULTI_HOST=1

# +++++++++++++++++++++
# LOGS & MO?ITORING
# +++++++++++++++++++++
DEBUG=True
VERBOSE=True
DEST=/opt/stack
LOGFILE=$DEST/logs/stack.sh.log
SCREEN_LOGDIR=/opt/stack/logs
SYSLOG=True
LOG_COLOR=True
LOGDAYS=7
ENABLE_DEBUG_LOG_LEVEL=True


# +++++++++++++++++++++++++++
# SERVICES CORE - CONTRÔLEUR
# +++++++++++++++++++++++++++
ENABLED_SERVICES=rabbit,mysql,key

# ++++++++++++++++++++++++
# HORIZON – INTERFACE WEB
# ++++++++++++++++++++++++
ENABLED_SERVICES+=,horizon

# ++++++++++++++++++++++++
# GLANCE – IMAGE SERVICE
# ++++++++++++++++++++++++
ENABLED_SERVICES+=,g-api,g-reg

# ++++++++++++++++++++++++
# NOVA – COMPUTE SERVICE
# ++++++++++++++++++++++++
ENABLED_SERVICES+=,n-api,n-crt,n-cpu,n-cond,n-sch,n-api-meta,n-sproxy,n-novnc n-cauth,placement-api,placement-client,n-net
LIBVIRT_TYPE=qemu

# +++++++++
# NEUTRON
# +++++++++
enable_plugin neutron https://opendev.org/openstack/neutron
ENABLED_SERVICES+=,neutron,q-svc,q-agt,q-dhcp,q-l3,q-meta,q-lbaas

# +++++++++++++++++++++++++++++++
# CINDER – BLOCK DEVICE SERVICE
# +++++++++++++++++++++++++++++++
ENABLED_SERVICES+=,cinder,c-api,c-vol,c-sch,c-bak
CINDER_DRIVER=ceph
CINDER_ENABLED_BACKENDS=ceph

# +++++++++++++++++++++++
# SWIFT (Object Storage)
# +++++++++++++++++++++++
ENABLED_SERVICES=swift3
ENABLED_SERVICES+=,s-proxy s-object s-container s-account
SWIFT_HASH=$(openssl rand -hex 16)
SWIFT_REPLICAS=1
SWIFT_DATA_DIR=$DEST/data/swift

# +++++++++++++++++++++++++++++
# Designate (DNS as a Service)
# +++++++++++++++++++++++++++++
enable_plugin designate https://opendev.org/openstack/designate
ENABLED_SERVICES+=,designate,designate-central,designate-api,designate-worker,designate-producer,designate-mdns
enable_plugin designate-dashboard https://opendev.org/openstack/designate-dashboard

# +++++++++++++++++++++
# HEAT (Orchestration)
# +++++++++++++++++++++
enable_plugin heat https://opendev.org/openstack/heat
ENABLED_SERVICES+=,h-eng h-api h-api-cfn h-api-cw

# +++++++++++++++++++++++++
# OCTAVIA (Load Balancing)
# +++++++++++++++++++++++++
enable_plugin octavia https://opendev.org/openstack/octavia
# Si vous activez Horizon, incluez le tableau de bord Octavia
enable_plugin octavia-dashboard https://opendev.org/openstack/octavia-dashboard.git
ENABLED_SERVICES+=,octavia,o-cw,o-hk,o-hm,o-api

# ++++++++++++++++++++++++++
# Barbican (Key Management)
# ++++++++++++++++++++++++++
# Si vous activez Barbican pour le déchargement TLS dans Octavia, incluez-le ici
enable_plugin barbican https://opendev.org/openstack/barbican
# Barbican - Utilisé en option pour le déchargement TLS dans Octavia
ENABLED_SERVICES+=,barbican

# +++++++
# Manila 
# +++++++
enable_plugin manila https://github.com/openstack/manila
enable_plugin manila-ui https://github.com/openstack/manila-u

# +++++
# CEPH 
# +++++
enable_plugin devstack-plugin-ceph https://github.com/openstack/devstack-plugin-ceph
ENABLED_SERVICES=ceph

# DevStack créera un disque en boucle formaté en XFS pour stocker les
# Ceph data.
CEPH_LOOPBACK_DISK_SIZE=30G
CEPH_CONF=/etc/ceph/ceph.conf

# Ceph cluster fsid
CEPH_FSID=$(uuidgen)

# Glance pool, pgs and user
GLANCE_CEPH_USER=glance
GLANCE_CEPH_POOL=glance
GLANCE_CEPH_POOL_PG=8
GLANCE_CEPH_POOL_PGP=8

# Nova pool and pgs
NOVA_CEPH_POOL=nova
NOVA_CEPH_POOL_PG=8
NOVA_CEPH_POOL_PGP=8

# Cinder pool, pgs and user
CINDER_DRIVER=ceph
CINDER_CEPH_POOL=cinder
CINDER_CEPH_USER=cinder
CINDER_CEPH_UUID=$(uuidgen)
CINDER_CEPH_POOL_PG=8
CINDER_CEPH_POOL_PGP=8

# Cinder backup pool, pgs and user
CINDER_BAK_CEPH_POOL=backup
CINDER_BAK_CEPH_POOL_PG=8
CINDER_BAKCEPH_POOL_PGP=8
CINDER_BAK_CEPH_USER=cinder-bak

# Combien de répliques doivent être configurées pour votre cluster Ceph
CEPH_REPLICAS=${CEPH_REPLICAS:-1}

# Connectez DevStack à un cluster Ceph existant
REMOTE_CEPH=False
REMOTE_CEPH_ADMIN_KEY_PATH=/etc/ceph/ceph.client.admin.keyring

# +++++++++++++++++++++++++++++++++++++
# CONFIGURATION CINDER (BLOCK STORAGE)
# +++++++++++++++++++++++++++++++++++++
CINDER_ENABLED_BACKENDS=lvm:cinder-volumes
VOLUME_GROUP=cinder-volumes
VOLUME_NAME_PREFIX="volume-"
VOLUME_BACKING_FILE_SIZE=0

# configuration du volume group pour cinder
[[post-config|$CINDER_CONF]]
[cinder-volumes]
image_volume_cache_enabled = True
volume_clear = zero
lvm_type = auto
target_prefix = iqn.2010-10.org.openstack:
target_port = 3260
target_protocol = iscsi
target_helper = lioadm
volume_group = cinder-volumes
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_backend_name = cinder-volumes

[DEFAULT]
enabled_backends = cinder-volumes
default_volume_type = cinder-volumes
storage_availability_zone = nova

# ++++++++++++++++++++++++++++++++
# CONFIGURATION NEUTRON (RÉSEAU)
# ++++++++++++++++++++++++++++++++
Q_AGENT=openvswitch
Q_ML2_TENANT_NETWORK_TYPE=vxlan
Q_ML2_PLUGIN_MECHANISM_DRIVERS=openvswitch,l2population
Q_TYPE_DRIVERS+=,flat,vlan,vxlan
Q_ML2_PLUGIN_EXT_DRIVERS=port_security

[ml2_type_vxlan]
vni_ranges = 1:1000

[ml2_type_flat]
flat_networks = public

[ovs]
bridge_mappings = public:br-ex

# +++++++++++++++++++++++++++++++
# CONFIGURATION DESIGNATE (DNS)
# +++++++++++++++++++++++++++++++
[[post-config|$DESIGNATE_CONF]]
[service:api]
listen = 0.0.0.0:9001
api_base_uri = http://192.168.1.121:9001/
auth_strategy = keystone
enable_api_v2 = True
enable_api_admin = True

[DEFAULT]
debug = True
default_pool_id = 794ccc2c-d751-44fe-b57f-8894c9f5c842

[service:worker]
enabled = True
notify = True

[service:mdns]
enabled = True

# +++++++++++++++++++++++++++++++++++++++
# CONFIGURATION OCTAVIA (LOAD BALANCER)
# +++++++++++++++++++++++++++++++++++++++
[[post-config|$OCTAVIA_CONF]]
[controller_worker]
amp_boot_network_list = $(neutron net-list | awk '/lb-mgmt-net/ {print $2}')
amp_flavor_id = 65

[DEFAULT]
debug = True

# Désactiver les services qui ne doivent pas tourner sur le contrôleur
DISABLE_SERVICE+=,n-cpu q-agt tempest,etcd3,tempest
```

### Lancer l’installation

```bash
# Exécutez stack.sh et effectuez quelques vérifications de cohérence
sudo su - stack
cd /opt/stack/devstack
./stack.sh

# Ce script télécharge, configure et déploie les services OpenStack sur le nœud contrôleur. Cela peut prendre du temps (10-30 minutes selon la machine).
```

### Vérifier l’installation

```bash
# Une fois terminé, vérifiez que les services sont en cours d’exécution
source openrc admin admin

openstack service list
openstack endpoint list

# Accédez à l’interface Horizon via un navigateur : http://<HOST_IP>/dashboard.
```


## 2. Configuration des nœuds compute
Les nœuds de calcul exécutent uniquement les services de travail OpenStack.

### Créer le fichier de configuration local.conf
Modifiez votre /opt/stack/devstack/local.conf pour qu'il ressemble à :

```bash
nano local.conf

[[local|localrc]]

# +++++++++++++++++++++
# CONFIGURATION RESEAU
# +++++++++++++++++++++
# Adresse IP du nœud compute (sur ton LAN)
HOST_IP=192.168.1.42

# Adresse IP du nœud contrôleur
SERVICE_HOST=192.168.1.121

# réseau (identique au controleur)
FIXED_RANGE=10.0.1.0/20
FLOATING_RANGE=192.168.1.120/25

# Interface réseau
PUBLIC_INTERFACE=ens34
FLAT_INTERFACE=ens34

# +++++++++++++++++++++++++
# CONFIGURATION MULTI-NŒUD
# +++++++++++++++++++++++++
MULTI_HOST=1

# ++++++++++++++++++++++++++++++++++++++++++++
# AUTHENTIFICATION (IDENTIQUES AU CONTRÔLEUR)
# ++++++++++++++++++++++++++++++++++++++++++++
ADMIN_PASSWORD=password
DATABASE_PASSWORD=password
RABBIT_PASSWORD=password
SERVICE_PASSWORD=password
SERVICE_TOKEN=password

# ++++++++++++++++++++++++++++++++
# CONNEXION AUX SERVICES CENTRAUX
# ++++++++++++++++++++++++++++++++
DATABASE_TYPE=mysql
MYSQL_HOST=$SERVICE_HOST
RABBIT_HOST=$SERVICE_HOST
GLANCE_HOSTPORT=$SERVICE_HOST:9292
Q_HOST=$SERVICE_HOST

# Keystone
KEYSTONE_AUTH_HOST=$SERVICE_HOST
KEYSTONE_SERVICE_HOST=$SERVICE_HOST

# +++++++++++++++++++++++++++++
# SERVICES ACTIVÉS SUR COMPUTE
# +++++++++++++++++++++++++++++
# Nova Compute (Hyperviseur)
ENABLED_SERVICES+=,n-cpu,c-vol,placement-client,ovn-controller,ovs-vswitchd,ovsdb-server,q-ovn-metadata-agent

# Neutron Agent (Réseau)
ENABLED_SERVICES+=,q-agt

# Monitoring Agent (optionnel)
# ENABLED_SERVICES+=,ceilometer-acompute

# +++++++++++++++++++++++++++
# CONFIGURATION NOVA COMPUTE
# +++++++++++++++++++++++++++
[[post-config|$NOVA_CONF]]
[DEFAULT]
# Type d'hyperviseur
compute_driver = libvirt.LibvirtDriver
vif_plugging_is_fatal = False
vif_plugging_timeout = 300

# VNC Configuration
NOVA_VNC_ENABLED=True
NOVNCPROXY_URL="http://$SERVICE_HOST:6080/vnc_lite.html"
VNCSERVER_LISTEN=$HOST_IP
VNCSERVER_PROXYCLIENT_ADDRESS=$VNCSERVER_LISTEN

[libvirt]
virt_type = qemu  # ou 'kvm' si pas de support QEMU
cpu_mode = host-passthrough
disk_cachemodes = network=writeback

[neutron]
auth_url = http://$SERVICE_HOST:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = neutron
password = $SERVICE_PASSWORD

# ++++++++++++++++++++++++++++
# CONFIGURATION NEUTRON AGENT
# ++++++++++++++++++++++++++++
[[post-config|/$Q_PLUGIN_CONF_FILE]]
[ovs]
bridge_mappings = public:br-ex
local_ip = $HOST_IP

[agent]
tunnel_types = vxlan
l2_population = True

[securitygroup]
firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

# ++++++++
# LOGGING
# ++++++++
# Enable Logging
LOGFILE=$DEST/logs/stack.sh.log
LOGDAYS=7
VERBOSE=True
LOG_COLOR=True

# +++++++++++++++++++++++++++++++++++++++++++++++
# SERVICES DÉSACTIVÉS (EXÉCUTENT SUR CONTRÔLEUR)
# +++++++++++++++++++++++++++++++++++++++++++++++
DISABLE_SERVICE=mysql rabbit key
DISABLE_SERVICE+=,horizon
DISABLE_SERVICE+=,g-api g-reg
DISABLE_SERVICE+=,n-api n-cond n-sch n-novnc n-cauth
DISABLE_SERVICE+=,c-api c-sch c-bak
DISABLE_SERVICE+=,q-svc q-dhcp q-l3 q-meta
DISABLE_SERVICE+=,s-proxy s-object s-container s-account
DISABLE_SERVICE+=,tempest
```

### Lancer l’installation

```bash
# Exécutez le script stack.sh
sudo su - stack
cd /opt/stack/devstack
./stack.sh

# Ce script télécharge, configure et déploie les services OpenStack sur le nœud compute. Cela peut prendre du temps (10-30 minutes selon la machine).
```

### Étape suivante à tester
Depuis le controller :

```bash
openstack service list
openstack endpoint list
openstack compute service list
openstack network agent list
```


## Nettoyage après DevStack
Arrêter OpenStack est aussi simple il suffit d’exécuter le shscript inclus :

```bash
./unstack.sh
./clean.sh

# Il arrive que les instances en cours d'exécution ne soient pas nettoyées. DevStack tente de le faire lors de son exécution, mais il arrive que cette opération doive être effectuée manuellement :
sudo rm -rf /etc/libvirt/qemu/inst*
sudo virsh list | grep inst | awk '{print $1}' | xargs -n1 virsh destroy
```


# Aller plus loin
# Utilisateurs supplémentaires

DevStack crée par défaut :

- Deux utilisateurs : **admin (administrateur)** et **demo (utilisateur standard)**.
- Deux projets : **admin** et **demo**.

Chaque utilisateur est membre d’un projet :

- **admin** → membre du projet **admin**
- **demo** → membre du projet **demo**

Un **projet** (ou tenant) est comme un **“compartiment”** ou une **“organisation”** qui contient des ressources (VM, volumes, réseaux…).
Un **utilisateur** appartient à un projet et a un rôle qui définit ce qu’il peut faire (admin, member…).

```bash
nano create_users.sh

#!/bin/bash
. /home/alcapone/devstack/openrc admin admin

# Créer utilisateur diegosoda
NAME=diegosoda
PASSWORD=adminuser
PROJECT=devops
openstack project create $PROJECT
openstack user create $NAME --password=$PASSWORD --project $PROJECT
openstack role add admin --user $NAME --project $PROJECT

# Créer utilisateur tubie
NAME=tubie
PASSWORD=adminuser
PROJECT=infra
openstack project create $PROJECT
openstack user create $NAME --password=$PASSWORD --project $PROJECT
openstack role add admin --user $NAME --project $PROJECT
```

### Exécuter le script

```bash
# Rendre le script exécutable
chmod +x create_users.sh

# # Exécutez le script create_users.sh
./create_users.sh
```

## Se connecter aux utilisateurs

### 1. Via l'interface web Horizon

- Connectez-vous à **Horizon** avec **chaque utilisateur**
- Allez dans **Project → API Access**
- Cliquez sur **Download OpenStack RC File → OpenStack clouds.yaml File**
- Le fichier sera automatiquement généré avec les bonnes informations

### 2. Où placer le fichier téléchargé ?

```bash
# Créer le répertoire de configuration
mkdir -p ~/.config/openstack

# Depuis Windows (PowerShell ou CMD)
scp "C:\Users\steph\Downloads\clouds.yaml" alcapone@192.168.1.121:~/.config/openstack/clouds.yaml

scp "C:\Users\steph\Downloads\devops-openrc.sh" alcapone@192.168.1.121:~
```

### 3. Vérification finale

```bash
# Vérifier la présence du fichier
ls -la ~/.config/openstack/clouds.yaml

# Vérifier le contenu
cat ~/.config/openstack/clouds.yaml
```

### Installer le client OpenStack

```bash
# Vérifiez la version de Python :
# Assurez-vous d'utiliser une version de Python compatible (par exemple, Python 3.6 ou supérieur). Vérifiez avec :
python3 --version

# Installez python-openstackclient
python3 -m venv alcapone
source alcapone/bin/activate
pip install --upgrade pip
pip install python-openstackclient

# Variables d’environnement
nano ~/.bashrc

# Ajouter ceci à la fin :
export OS_CLOUD=diegosoda
source alcapone/bin/activate

# Redémarrer :
Ctrl+D

# Test maintenant
echo "Cloud actuel: $OS_CLOUD"
openstack token issue
```


