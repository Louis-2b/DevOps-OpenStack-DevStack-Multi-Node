# Déploiement OpenStack avec DevStack

Ce guide documente les étapes complètes pour préparer un serveur, installer et déployer OpenStack en utilisant **DevStack** sur un **OS DEBIAN 12**.

## Prérequis généraux

### Matériel :

Minimum **2 machines (1 contrôleur + 1 compute)**.
Chaque machine doit avoir au moins **10 Go de RAM ou plus**, **8 cœurs CPU ou plus**, deux espace disque sur la machine **contrôleur** et un espace disque sur la machine **compute**  **(100 Go recommandé ou plus)** et deux cartes réseaux en mode **Bridged**.
Système d'exploitation : **Debian 12**.

---

## 1. Préparation du système (A faire sur les 2 machines 1 contrôleur + 1 compute)

```bash
su -
apt update -y && apt upgrade -y
apt install sudo git -y
```

### Configurer sudo sans mot de passe

```bash
sudo visudo
```
Ajouter :

```
alcapone   ALL=(ALL:ALL) NOPASSWD:ALL
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
cat ~/.ssh/devstack.pub | ssh alcapone@192.168.1.41 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# Tester la connexion
ssh -i ~/.ssh/devstack alcapone@192.168.1.41
```

### Téléchargement de DevStack sur les 2 machines (1 contrôleur + 1 compute)

Avant de lancer DevStack, assure toi d'avoir :
```bash
sudo apt install -y git python3-pip lvm2 thin-provisioning-tools python3-venv libpq-dev python3-dev
```

```bash
git clone https://opendev.org/openstack/devstack
cd devstack
```


# Étapes d’installation

## 1. Configuration du nœud contrôleur
Le nœud contrôleur exécute tous les services OpenStack.

### Créer le fichier de configuration local.conf

```bash
nano local.conf


[[local|localrc]]

# +++++++++++++++++++++
# CONFIGURATION RESEAU
# +++++++++++++++++++++
# Adresse IP du nœud contrôleur (celle de ta machine sur le LAN)
HOST_IP=192.168.1.121
SERVICE_HOST=192.168.1.121

# Plage réseau interne pour les instances (ne doit pas entrer en conflit avec ton LAN)
FIXED_RANGE=10.0.1.0/20

# Plage d’adresses IP flottantes (doit appartenir au même réseau que HOST_IP)
FLOATING_RANGE=192.168.1.120/25

# interface reliée au LAN externe (pas d’IP assignée directement)
PUBLIC_INTERFACE=ens34

# utilisée par Neutron pour le réseau provider
FLAT_INTERFACE=ens34

# DNS pour les instances
DNS_SERVERS=8.8.8.8,8.8.4.4

# ++++++++++++++++++++++++++++
# AUTHENTIFICATION & SECURITE
# ++++++++++++++++++++++++++++
ADMIN_PASSWORD=OpenStack2026!Secure
DATABASE_PASSWORD=DbP@ssw0rd2026!
RABBIT_PASSWORD=RabbitMQ!2026
SERVICE_PASSWORD=ServiceP@ss2026!

# Keystone (Identity)
KEYSTONE_TONE_FORMAT=fermet

# +++++++++++++++++++++++++++
# SERVICES CORE - CONTRÔLEUR
# +++++++++++++++++++++++++++
# Base de données
enable_service mysql

# Message Queue
enable_service rabbit

# Keystone (Identity)
enable_service key

# Horizon (Dashboard)
enable_service horizon

# Glance (Image Service)
enable_service g-api g-reg

# Nova (Compute Controller)
enable_service n-api n-cond n-sch n-novnc n-cauth
disable_service n-cpu  # Pas de compute sur contrôleur

# Placement API
enable_service placement-api placement-client

# Neutron (Network Controller)
enable_plugin neutron https://opendev.org/openstack/neutron
enable_service q-svc q-dhcp q-meta q-l3
disable_service q-agt  # Agent sur compute uniquement

# Cinder (Block Storage Controller)
enable_service c-api c-sch c-vol c-bak

# ++++++++++++++++++++++
# SERVICES ADDITIONNELS
# ++++++++++++++++++++++
# Swift (Object Storage)
enable_service s-proxy s-object s-container s-account
SWIFT_HASH=$(openssl rand -hex 16)
SWIFT_REPLICAS=1
SWIFT_DATA_DIR=$DEST/data/swift

# Designate (DNS as a Service)
enable_plugin designate https://opendev.org/openstack/designate
enable_service designate,designate-central,designate-api,designate-worker,designate-producer,designate-mdns
enable_plugin designate-dashboard https://opendev.org/openstack/designate-dashboard

# Heat (Orchestration)
enable_plugin heat https://opendev.org/openstack/heat
enable_service h-eng h-api h-api-cfn h-api-cw

# Octavia (Load Balancing)
enable_plugin octavia https://opendev.org/openstack/octavia
enable_plugin octavia-dashboard https://opendev.org/openstack/octavia-dashboard
enable_service octavia o-cw o-hk o-hm o-api

# Barbican (Key Management)
enable_plugin barbican https://opendev.org/openstack/barbican
enable_service barbican

# +++++++++++++++++++++++++++++++++++++
# CONFIGURATION CINDER (BLOCK STORAGE)
# +++++++++++++++++++++++++++++++++++++
CINDER_ENABLED_BACKENDS=lvm:cinder-volumes
VOLUME_GROUP=cinder-volumes
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
[[post-config|/$Q_PLUGIN_CONF_FILE]]
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = openvswitch,l2population
extension_drivers = port_security

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

# +++++++++++++++++++++
# LOGS & MO?ITORING
# +++++++++++++++++++++
# Emplacement du fichier de logs
LOGFILE=/opt/stack/logs/stack.sh.log
LOGDAYS=7
VERBOSE=True
LOG_COLOR=True
ENABLE_DEBUG_LOG_LEVEL=True

# Désactiver les services qui ne doivent pas tourner sur le contrôleur
disable_service n-cpu q-agt tempest
disable_service tempest
disable_service etcd3

# +++++++++++++++++++++++++
# CONFIGURATION MULTI-NOEUD
# +++++++++++++++++++++++++
MULTI_HOST=1
```

### Lancer l’installation

```bash
# Exécutez le script stack.sh
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

```bash
nano local.conf

[[local|localrc]]

# +++++++++++++++++++++
# CONFIGURATION RESEAU
# +++++++++++++++++++++
# Adresse IP du nœud compute (celle de ta machine sur le LAN)
HOST_IP=192.168.1.42
SERVICE_HOST=192.168.1.121  # Adresse IP du nœud contrôleur

# réseau (identique au controleur)
FIXED_RANGE=10.0.1.0/20
FLOATING_RANGE=192.168.1.120/25
PUBLIC_INTERFACE=ens34
FLAT_INTERFACE=ens34

# ++++++++++++++++++++++++++++++++++++++++++++
# AUTHENTIFICATION (IDENTIQUES AU CONTRÔLEUR)
# ++++++++++++++++++++++++++++++++++++++++++++
ADMIN_PASSWORD=OpenStack2025!Secure
DATABASE_PASSWORD=DbP@ssw0rd2025!
RABBIT_PASSWORD=RabbitMQ!2025
SERVICE_PASSWORD=ServiceP@ss2025!

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
ENABLED_SERVICES=n-cpu

# Placement Client
ENABLED_SERVICES+=,placement-client

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
vnc_enabled = True
novncproxy_base_url = http://$SERVICE_HOST:6080/vnc_lite.html
vncserver_listen = 0.0.0.0
vncserver_proxyclient_address = $HOST_IP

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




# Emplacement du fichier de logs
LOGFILE=/opt/stack/logs/stack.sh.log
LOGDAYS=2

# Configuration multi-nœud
MULTI_HOST=1


# Configuration VNC pour console
NOVA_VNC_ENABLED=True
NOVNCPROXY_URL="http://$SERVICE_HOST:6080/vnc_lite.html"
VNCSERVER_LISTEN=$HOST_IP
VNCSERVER_PROXYCLIENT_ADDRESS=$VNCSERVER_LISTEN

# Désactiver les services qui ne doivent pas tourner sur compute
disable_service tempest
disable_service n-api n-sch n-cond n-obj n-crt
disable_service c-api c-vol c-sch c-bak
disable_service g-api g-reg
disable_service horizon
disable_service mysql rabbit key
disable_service q-svc q-dhcp q-l3 q-meta
```

### Lancer l’installation

```bash
# Exécutez le script stack.sh
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


