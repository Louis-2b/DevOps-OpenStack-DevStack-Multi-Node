# Déploiement OpenStack avec DevStack
Ce guide documente les étapes complètes pour préparer un serveur, 
installer et déployer OpenStack via DevStack sur Debian 12 (Bookworm).

> ⚠️ Debian 13 (Trixie) est encore en phase de test — préférer Debian 12 
> pour un environnement stable.


## Prérequis généraux

### Ressources minimales recommandées
| Rôle        | RAM    | vCPU | Disque |
|-------------|--------|------|--------|
| Contrôleur  | 8 Go   | 4    | 100 Go |
| Compute     | 4 Go   | 2    | 50 Go  |

---

## 1. Préparation du système
> À effectuer sur les 2 machines (contrôleur + compute)

### Étape 1 : Configuration réseau statique
Passer en root (sudo non installé par défaut sur Debian) :

    su -

Vérifier le nom de vos interfaces réseau :

    ip a

Éditer la configuration :

    nano /etc/network/interfaces

#### Avant (DHCP) :
    allow-hotplug ens33
    iface ens33 inet dhcp
    iface ens33 inet6 auto

#### Après (IP statique) :

    # Interface de management (ens33)
    # Contrôleur : 172.20.10.3 | Compute : 172.20.10.4
    allow-hotplug ens33
    iface ens33 inet static
        address 172.20.10.3        # ← adapter selon le nœud
        netmask 255.255.255.240
        gateway 172.20.10.1
        dns-nameservers 8.8.8.8 1.1.1.1

    # Interface bridge externe (ens34) — sans IP, gérée par OpenStack
    allow-hotplug ens34
    iface ens34 inet manual
        up ip link set dev $IFACE up
        down ip link set dev $IFACE down

Sauvegarder : Ctrl+O → Entrée → Ctrl+X

Appliquer :

    systemctl restart networking

Vérifier :

    ip a
    ip route

### Étape 2 : Mises à jour système

    apt update && apt upgrade -y







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
[[local|localrc]]

# +++++++++++++++++++++
# CONFIGURATION RESEAU
# +++++++++++++++++++++
HOST_IP=192.168.1.121
SERVICE_HOST=192.168.1.121

# Plage réseau interne (pour les instances)
FIXED_RANGE=10.0.1.0/24
FIXED_NETWORK_SIZE=256

# Plage d’adresses IP flottantes
FLOATING_RANGE=192.168.1.122/27
Q_FLOATING_ALLOCATION_POOL=start=192.168.1.123,end=192.168.1.130

# interface reliée au LAN externe
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
KEYSTONE_TOKEN_FORMAT=fernet
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

# CONFIGURATION NEUTRON (RÉSEAU)
Q_AGENT=openvswitch
Q_ML2_TENANT_NETWORK_TYPE=vxlan
Q_ML2_PLUGIN_MECHANISM_DRIVERS=openvswitch,l2population
Q_ML2_PLUGIN_TYPE_DRIVERS=flat,vlan,vxlan
Q_ML2_PLUGIN_EXT_DRIVERS=port_security

# +++++++++++++++++++++++++++++++
# CINDER – BLOCK DEVICE SERVICE
# +++++++++++++++++++++++++++++++
ENABLED_SERVICES+=,cinder,c-api,c-vol,c-sch,c-bak
#CINDER_DRIVER=ceph
#CINDER_ENABLED_BACKENDS=ceph

# +++++++++++++++++++++++
# SWIFT (Object Storage)
# +++++++++++++++++++++++
ENABLED_SERVICES+=,swift
ENABLED_SERVICES+=,s-proxy s-object s-container s-account
SWIFT_HASH=$(openssl rand -hex 16)
SWIFT_REPLICAS=1
SWIFT_DATA_DIR=$DEST/data/swift

# +++++++++++++++++++++++++++++
# Designate (DNS as a Service)
# +++++++++++++++++++++++++++++
enable_plugin designate https://opendev.org/openstack/designate
enable_plugin designate-dashboard https://opendev.org/openstack/designate-dashboard
ENABLED_SERVICES+=,designate,designate-central,designate-api,designate-worker,designate-producer,designate-mdns

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

# ++++++++++++++++++++++++++++
# Manila (Shared Filesystems)
# ++++++++++++++++++++++++++++
enable_plugin manila https://github.com/openstack/manila
enable_plugin manila-ui https://github.com/openstack/manila-ui

# +++++
# CEPH 
# +++++
#enable_plugin devstack-plugin-ceph https://github.com/openstack/devstack-plugin-ceph
#ENABLED_SERVICES=ceph

# DevStack créera un disque en boucle formaté en XFS pour stocker les
# Ceph data.
#CEPH_LOOPBACK_DISK_SIZE=30G
#CEPH_CONF=/etc/ceph/ceph.conf

# Ceph cluster fsid
#CEPH_FSID=$(uuidgen)

# Glance pool, pgs and user
#GLANCE_CEPH_USER=glance
#GLANCE_CEPH_POOL=glance
#GLANCE_CEPH_POOL_PG=8
#GLANCE_CEPH_POOL_PGP=8

# Nova pool and pgs
#NOVA_CEPH_POOL=nova
#NOVA_CEPH_POOL_PG=8
#NOVA_CEPH_POOL_PGP=8

# Cinder pool, pgs and user
#CINDER_DRIVER=ceph
#CINDER_CEPH_POOL=cinder
#CINDER_CEPH_USER=cinder
#CINDER_CEPH_UUID=$(uuidgen)
#CINDER_CEPH_POOL_PG=8
#CINDER_CEPH_POOL_PGP=8

# Cinder backup pool, pgs and user
#CINDER_BAK_CEPH_POOL=backup
#CINDER_BAK_CEPH_POOL_PG=8
#CINDER_BAKCEPH_POOL_PGP=8
#CINDER_BAK_CEPH_USER=cinder-bak

# Combien de répliques doivent être configurées pour votre cluster Ceph
#CEPH_REPLICAS=${CEPH_REPLICAS:-1}

# Connectez DevStack à un cluster Ceph existant
#REMOTE_CEPH=False
#REMOTE_CEPH_ADMIN_KEY_PATH=/etc/ceph/ceph.client.admin.keyring

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

# +++++++++++++++++++++
# POST-CONFIG: NEUTRON
# +++++++++++++++++++++
[[POST6CONFIG|/$Q_PLUGIN_CONF_FILE]]
[ml2]
type_drivers=flat,vlan,vxlan
tenant_network_type=vxlan
mechanism_drivers=openvswitch,l2population
extension_drivers=port_security

[ml2_type_vxlan]
vni_ranges = 1:1000

[ml2_type_flat]
flat_networks = public

[ovs]
bridge_mappings = public:br-ex
local_ip=£HOST_IP

[agent]
tunnel_types=vxlan
l2_population=True

# +++++++++++++++++++++++++++++++
# POST-CONFIG DESIGNATE (DNS)
# +++++++++++++++++++++++++++++++
[[post-config|$DESIGNATE_CONF]]
[service:api]
listen = 0.0.0.0:9001
api_base_uri=http://$SERVICE_HOST:9001/
auth_strategy=keystone
enable_api_v2=True
enable_api_admin=True

[DEFAULT]
debug=True
default_pool_id=794ccc2c-d751-44fe-b57f-8894c9f5c842

[service:worker]
enabled=True
notify=True

[service:mdns]
enabled=True

# +++++++++++++++++++++++++++++++++++++++
# CONFIGURATION OCTAVIA (LOAD BALANCER)
# +++++++++++++++++++++++++++++++++++++++
[[post-config|$OCTAVIA_CONF]]
[controller_worker]
amp_boot_network_list=$(neutron net-list | awk '/lb-mgmt-net/ {print $2}')
amp_flavor_id=65

[DEFAULT]
debug=True

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
[[local|localrc]]

# +++++++++++++++++++++
# CONFIGURATION RESEAU
# +++++++++++++++++++++
# Adresse IP du nœud compute (sur ton LAN)
HOST_IP=192.168.1.42

# Adresse IP du nœud contrôleur
SERVICE_HOST=192.168.1.121

# réseau (identique au controleur)
FIXED_RANGE=10.0.1.0/24
FIXED_NETWORK_SIZE=256
FLOATING_RANGE=192.168.1.122/27
Q_FLOATING_ALLOCATION_POOL=start=192.168.1.123,end=192.168.1.130

# Interface réseau
PUBLIC_INTERFACE=ens34
FLAT_INTERFACE=$PUBLIC_INTERFACE

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
KEYSTONE_TOKEN_FORMAT=fernet

# +++++++++++++++++++++++++++++
# SERVICES ACTIVÉS SUR COMPUTE
# +++++++++++++++++++++++++++++
# IMPORTANT: Sur Compute on active uniquement n-cpu et q-agt
ENABLED_SERVICES=n-cpu,q-agt,placement-client

# +++++++++++++++++++++++++++
# CONFIGURATION NOVA COMPUTE
# +++++++++++++++++++++++++++
# Type d'hyperviseur
# ou 'kvm' si pas de support QEMU
LIBVIRT_TYPE=qemu

# VNC Configuration
NOVA_VNC_ENABLED=True
NOVNCPROXY_URL="http://$SERVICE_HOST:6080/vnc_lite.html"
VNCSERVER_LISTEN=$HOST_IP
VNCSERVER_PROXYCLIENT_ADDRESS=$HOST_IP


# ++++++++++++++++++++++
# CONFIGURATION NEUTRON
# ++++++++++++++++++++++
enable_plugin neutron https://opendev.org/openstack/neutron

# Configuration OVS
Q_AGENT=openvswitch
Q_ML2_TENANT_NETWORK_TYPE=vxlan
Q_ML2_PLUGIN_MECHANISM_DRIVERS=openvswitch,l2population

# ++++++++
# LOGGING
# ++++++++
DEST=/opt/stack
LOGFILE=$DEST/logs/stack.sh.log
SCREEN_LOGDIR=$DEST/logs
LOGDAYS=7
VERBOSE=True
DEBUG=True
LOG_COLOR=True
ENABLE_DEBUG_LOG_LEVEL=True

# ++++++++++++++++++++++++++
# POST-CONFIG: NOVA COMPUTE
# ++++++++++++++++++++++++++
[[post-config|$NOVA_CONF]]
[DEFAULT]
compute_driver=libvirt.LibvirtDriver
vif_plugging_is_fatal=False
vif_plugging_timeout=300

[vnc]
enabled=True
server_listen=0.0.0.0
server_proxyclient_address=$HOST_IP
novncproxy_base_url=http://192.168.1.121:6080/vnc_lite.html

[libvirt]
virt_type=qemu
cpu_mode=host-passthrough
disk_cachemodes=network=writeback

[neutron]
auth_url=http://192.168.1.121:5000
auth_type=password
project_domain_name=Default
user_domain_name=Default
region_name=RegionOne
project_name=service
username=neutron
password=password

[placement]
region_name=RegionOne
project_domain_name=Default
project_name=service
auth_type=password
user_domain_name=Default
auth_url=http://192.168.1.121:5000
username=placement
password=password

# +++++++++++++++++++++++++++
# POST-CONFIG: NEUTRON AGENT
# +++++++++++++++++++++++++++
[[post-config|/$Q_PLUGIN_CONF_FILE]]
[ovs]
bridge_mappings=public:br-ex
local_ip=192.168.1.42

[agent]
tunnel_types=vxlan
l2_population=True

[securitygroup]
firewall_driver=neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

# +++++++++++++++++++++++++++++++++++++++++++++++
# SERVICES DÉSACTIVÉS (EXÉCUTENT SUR CONTRÔLEUR)
# +++++++++++++++++++++++++++++++++++++++++++++++
# Services de base
disable_service mysql rabbit key

# Horizon
disable_service horizon

# Glance
disable_service g-api g-reg

# Nova API services
disable_service n-api n-cond n-sch n-novnc n-cauth n-api-meta n-sproxy

# Cinder API services (volume reste sur contrôleur)
disable_service cinder c-api c-sch c-vol c-bak

# Neutron services centraux
disable_service q-svc q-dhcp q-l3 q-meta

# Swift
disable_service s-proxy s-object s-container s-account

# Services additionnels
disable_service tempest etcd3

# Heat
disable_service h-eng h-api h-api-cfn h-api-cw

# Designate
disable_service designate designate-central designate-api designate-worker designate-producer designate-mdns

# Octavia
disable_service octavia o-cw o-hk o-hm o-api

# Barbican
disable_service barbican
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


