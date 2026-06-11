# Déploiement OpenStack avec DevStack
Ce guide documente les étapes complètes pour préparer un serveur, 
installer et déployer OpenStack via DevStack sur Debian 12 (Bookworm).

> ⚠️ Debian 13 (Trixie) est encore en phase de test — préférer Debian 12 
> pour un environnement stable.

## Prérequis généraux

### Ressources recommandées

| Rôle           | RAM   | vCPU | Disque        |
|----------------|-------|------|---------------|
| Contrôleur     | 16 Go | 4    | 2x 100 Go SSD |
| Compute        | 32 Go | 8    | 2x 500 Go SSD |
| Stockage Ceph  | 8 Go  | 2    | 3x 1 To       |  

---

## 1. Préparation du système
> À effectuer sur les 2 machines (contrôleur + compute)

### Étape 1 : Configuration réseau statique

Passer en root (sudo non installé par défaut sur Debian) :

    su -

Vérifier le nom de vos interfaces réseau :

    ip a

> ⚠️ Les noms d'interfaces peuvent varier (ens33, ens36, eth0...).
> Adaptez les noms dans la configuration selon votre machine.

Éditer la configuration :

    nano /etc/network/interfaces

#### Avant (DHCP) :

    allow-hotplug ens33
    iface ens33 inet dhcp
    iface ens33 inet6 auto

#### Après (IP statique) :

    # Interface de management (ens33)
    # Contrôleur : 172.20.10.5 | Compute : 172.20.10.6
    allow-hotplug ens33
    iface ens33 inet static
        address 172.20.10.5        # ← adapter selon le nœud
        netmask 255.255.255.240
        gateway 172.20.10.1
        dns-nameservers 8.8.8.8 1.1.1.1

    # Interface bridge externe (ens36) — sans IP, gérée par OpenStack
    # Vérifier le nom exact avec : ip a
    allow-hotplug ens36
    iface ens36 inet manual
        up ip link set dev $IFACE up
        down ip link set dev $IFACE down

Sauvegarder : Ctrl+O → Entrée → Ctrl+X

Appliquer :

    systemctl restart networking

Vérifier :

    ip a
    ip route

---

### Étape 2 : Installation de sudo et mises à jour

Par défaut sur Debian, sudo n'est pas installé. En tant que root :

    apt install sudo -y

Ajouter votre utilisateur principal au groupe sudo (optionnel) :

    usermod -aG sudo <votre_utilisateur>

Appliquer les mises à jour système :

    sudo apt update && apt upgrade -y

---

### Étape 3 : Informations et vérification du système

Avant de continuer, vérifier les ressources disponibles :

    lsb_release -a      # version Debian
    nproc               # nombre de CPUs
    free -mh            # mémoire disponible
    df -h /             # espace disque
    id                  # utilisateur courant

---

### Étape 4 : Vérification et activation de KVM

Installer les outils de vérification :

    sudo apt install qemu-kvm -y
    sudo apt install libvirt-clients -y
    sudo virt-host-validate

> ✅ Résultat attendu : PASS sur les lignes QEMU et KVM.
> ❌ Si FAIL sur KVM : la virtualisation n'est pas activée dans le BIOS.

Vérifier si les modules sont déjà chargés :

    lsmod | grep kvm

#### Pour processeur Intel :

    sudo modprobe kvm-intel
    echo 'options kvm-intel nested=1' | sudo tee /etc/modprobe.d/kvm-intel.conf

Rendre le module permanent au démarrage :

    echo 'kvm-intel' | sudo tee -a /etc/modules

Vérifier que la virtualisation imbriquée est active :

    cat /sys/module/kvm_intel/parameters/nested
    # Résultat attendu : Y ou 1

#### Pour processeur AMD :

    modprobe kvm-amd
    echo 'options kvm-amd nested=1' | sudo tee /etc/modprobe.d/kvm-amd.conf

Rendre le module permanent au démarrage :

    echo 'kvm-amd' | sudo tee -a /etc/modules

Vérifier que la virtualisation imbriquée est active :

    cat /sys/module/kvm_amd/parameters/nested
    # Résultat attendu : Y ou 1

---

### Étape 5 : Création de l'utilisateur stack

DevStack doit être exécuté avec un utilisateur dédié (jamais en root) :

    sudo useradd -s /bin/bash -d /opt/stack -m stack
    echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack
    sudo chmod 0440 /etc/sudoers.d/stack

Basculer vers l'utilisateur stack :

    sudo su - stack

Vérifier :

    whoami        # doit afficher : stack
    sudo -l       # doit afficher les droits NOPASSWD

---


### Étape 6 : Configuration du stockage

#### Sur le CONTRÔLEUR — Cinder (volumes bloc)

Vérification des disques disponibles

    lsblk

> Résultat attendu : sda (système) + sdb (vierge, sans partition)

Vérifier que sdb est bien vierge :

    sudo wipefs -a /dev/sdb        # efface toute signature existante

#### Configuration LVM pour Cinder

    sudo apt install lvm2 -y
    sudo pvcreate /dev/sdb
    sudo vgcreate cinder-volumes /dev/sdb

Vérifier :

    sudo pvs        # affiche le volume physique
    sudo vgs        # affiche le groupe de volumes

> Résultat attendu :
>   VG             #PV  #LV  #SN  Attr  VSize  VFree
>   cinder-volumes   1    0    0  wz--n  XX.XXg  XX.XXg

---

#### Sur le COMPUTE — Nova (disques éphémères des VMs)

Vérification des disques disponibles

    lsblk

> Résultat attendu : sda (système) + sdb (vierge)

#### Formatage et montage de sdb pour Nova

    sudo mkfs.ext4 /dev/sdb

Créer le point de montage :

    sudo mkdir -p /opt/stack/data/nova/instances

Monter le disque :

    sudo mount /dev/sdb /opt/stack/data/nova/instances

Rendre le montage permanent au redémarrage :

    echo '/dev/sdb /opt/stack/data/nova/instances ext4 defaults 0 2' | sudo tee -a /etc/fstab

Vérifier que la ligne a bien été ajoutée :

    cat /etc/fstab
    
Puis vérifier le montage :

    df -h /opt/stack/data/nova/instances

---


### Étape 7 : Configuration SSH et installation de DevStack

#### Sur le CONTRÔLEUR — Génération de la paire de clés SSH

Se connecter en tant que stack :

    sudo su - stack

Générer la paire de clés (Ed25519 recommandé) :

    ssh-keygen -t ed25519 -C "devstack" -f ~/.ssh/devstack

> Appuyer sur Entrée pour laisser la passphrase vide (plus pratique 
> pour DevStack).

Copier la clé publique vers le nœud compute :

    ssh-copy-id -i ~/.ssh/devstack.pub diegosoda@172.20.10.5

Tester la connexion :

    ssh -i ~/.ssh/devstack diegosoda@172.20.10.6

> ✅ Résultat attendu : connexion sans mot de passe.

---

#### Sur les 2 machines — Installation des dépendances

En tant que root :

    sudo apt install -y git python3-pip python3-dev python3-venv \
        libffi-dev libssl-dev libpq-dev \
        gcc bridge-utils lvm2 thin-provisioning-tools

---

#### Sur les 2 machines — Clonage de DevStack

Basculer vers l'utilisateur stack :

    sudo su - stack

Cloner DevStack directement dans /opt/stack :

    git clone https://opendev.org/openstack/devstack /opt/stack/devstack

---

#### Vérification de la connectivité entre les nœuds

Depuis le contrôleur vers le compute :

    ping -c 3 172.20.10.6

Depuis le compute vers le contrôleur :

    ping -c 3 172.20.10.5

> ✅ Les deux doivent répondre avant de continuer.

---


## 4. Installation de DevStack

### Sur le CONTRÔLEUR

#### Étape 8 : Créer le fichier local.conf

Se connecter en tant que stack :

    sudo su - stack
    cd /opt/stack/devstack

Générer la clé KEK pour Barbican avant de créer le fichier :

    python3 -c "import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())"

> ⚠️ Copier la clé générée — elle sera à coller dans le champ `kek` 
> du fichier local.conf ci-dessous.

Créer le fichier de configuration :

    sudo nano /opt/stack/devstack/local.conf

Contenu du fichier (remplacer `REMPLACER_PAR_CLE_GENEREE` par la clé copiée) :

    # ++++++++++++++++++++++++++++++++++++
    # ++++ Local controller · CONF(1) ++++
    # ++++++++++++++++++++++++++++++++++++
    
    [[local|localrc]]
    
    # ++++++++++++++++++++
    # CONFIGURATION RESEAU
    # ++++++++++++++++++++
    HOSTNAME=controller
    HOST_IP=172.20.10.5
    SERVICE_HOST=172.20.10.5
    
    FIXED_RANGE=10.0.1.0/24
    FIXED_NETWORK_SIZE=256
    NETWORK_GATEWAY=10.0.1.1
    
    # Floating IPs — Contrôleur=.5 | Compute=.6 | Floating=.7 à .14
    FLOATING_RANGE=172.20.10.0/28
    Q_FLOATING_ALLOCATION_POOL=start=172.20.10.7,end=172.20.10.14
    
    PUBLIC_INTERFACE=ens36
    FLAT_INTERFACE=ens36
    
    PUBLIC_NETWORK_GATEWAY=172.20.10.1
    DNS_SERVERS=8.8.8.8,1.1.1.1
    
    # +++++++++++++++++++++++++++
    # AUTHENTIFICATION & SECURITE
    # +++++++++++++++++++++++++++
    ADMIN_PASSWORD=password
    DATABASE_PASSWORD=password
    RABBIT_PASSWORD=password
    SERVICE_PASSWORD=password
    
    # +++++++++++++++++++
    # Keystone (Identity)
    # +++++++++++++++++++
    KEYSTONE_TOKEN_FORMAT=fernet
    KEYSTONE_CATALOG_BACKEND=sql
    
    # +++++++++++++++++++++++++
    # CONFIGURATION MULTI-NOEUD
    # +++++++++++++++++++++++++
    MULTI_HOST=1
    
    # +++++++++++++++++
    # LOGS & MONITORING
    # +++++++++++++++++
    DEBUG=True
    VERBOSE=True
    DEST=/opt/stack
    LOGFILE=$DEST/logs/stack.sh.log
    SCREEN_LOGDIR=$DEST/logs
    SYSLOG=False
    LOG_COLOR=True
    LOGDAYS=7
    
    # ++++++++++++++++++++++++++
    # SERVICES CORE - CONTROLEUR
    # ++++++++++++++++++++++++++
    ENABLED_SERVICES=rabbit,mysql,key
    
    # +++++++++++++++++++++++
    # HORIZON - INTERFACE WEB
    # +++++++++++++++++++++++
    ENABLED_SERVICES+=,horizon
    
    # +++++++++++++++++++++++++++++++++++
    # GLANCE - IMAGE SERVICE
    # g-reg retiré (déprécié depuis Yoga)
    # +++++++++++++++++++++++++++++++++++
    ENABLED_SERVICES+=,g-api
    
    # +++++++++++++++++++++++++++++++++++++++++++++
    # NOVA - COMPUTE SERVICE
    # n-cpu retiré du contrôleur (rôle du compute)
    # n-sproxy et n-cauth retirés (dépréciés Yoga+)
    # +++++++++++++++++++++++++++++++++++++++++++++
    ENABLED_SERVICES+=,n-api,n-crt,n-cond,n-sch,n-api-meta,n-novnc,placement-api,placement-client
    LIBVIRT_TYPE=kvm
    
    # ++++++++++++++++
    # NEUTRON - Réseau
    # ++++++++++++++++
    enable_plugin neutron https://opendev.org/openstack/neutron
    ENABLED_SERVICES+=,neutron,q-svc,q-agt,q-dhcp,q-l3,q-meta
    
    Q_AGENT=openvswitch
    Q_ML2_PLUGIN_TENANT_NETWORK_TYPES=vxlan,geneve
    Q_ML2_PLUGIN_MECHANISM_DRIVERS=openvswitch,l2population
    Q_ML2_PLUGIN_TYPE_DRIVERS=flat,vlan,vxlan,geneve
    Q_ML2_PLUGIN_EXT_DRIVERS=port_security
    Q_ML2_PLUGIN_VNI_RANGES=1:1000
    
    # +++++++++++++++++++++
    # CINDER - Volumes bloc
    # +++++++++++++++++++++
    ENABLED_SERVICES+=,cinder,c-api,c-vol,c-sch,c-bak
    CINDER_ENABLED_BACKENDS=lvm:cinder-volumes
    VOLUME_GROUP=cinder-volumes
    VOLUME_NAME_PREFIX=volume-
    
    # ++++++++++++++++++++++
    # SWIFT - Stockage objet
    # ++++++++++++++++++++++
    ENABLED_SERVICES+=,swift,s-proxy,s-object,s-container,s-account
    SWIFT_HASH=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6
    SWIFT_REPLICAS=1
    SWIFT_DATA_DIR=$DEST/data/swift
    
    # ++++++++++++++++++++
    # HEAT - Orchestration
    # ++++++++++++++++++++
    enable_plugin heat https://opendev.org/openstack/heat
    ENABLED_SERVICES+=,h-eng,h-api,h-api-cfn
    
    # +++++++++++++++++++++++++++
    # BARBICAN - Gestion des clés
    # +++++++++++++++++++++++++++
    enable_plugin barbican https://opendev.org/openstack/barbican
    ENABLED_SERVICES+=,barbican,barbican-api,barbican-worker,barbican-keystone-listener
    
    # ++++++++++++++++++++++++++++
    # DESIGNATE - DNS as a Service
    # ++++++++++++++++++++++++++++
    enable_plugin designate https://opendev.org/openstack/designate
    enable_plugin designate-dashboard https://opendev.org/openstack/designate-dashboard
    ENABLED_SERVICES+=,designate,designate-central,designate-api,designate-worker,designate-producer,designate-mdns
    
    # +++++++++++++++++++
    # SERVICES DESACTIVES
    # +++++++++++++++++++
    disable_service tempest etcd3
    
    # +++++++++++
    # POST-CONFIG
    # +++++++++++
    
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
    
    [[post-config|/etc/neutron/plugins/ml2/ml2_conf.ini]]
    [ml2]
    type_drivers = flat,vlan,vxlan,geneve
    tenant_network_types = vxlan,geneve
    mechanism_drivers = openvswitch,l2population
    extension_drivers = port_security
    
    [ml2_type_vxlan]
    vni_ranges = 1:1000
    
    [ml2_type_flat]
    flat_networks = public
    
    [ovs]
    bridge_mappings = public:br-ex
    local_ip = 172.20.10.5
    
    [agent]
    tunnel_types = vxlan
    l2_population = True
    
    [[post-config|$BARBICAN_CONF]]
    [DEFAULT]
    debug = True
    host_href = http://172.20.10.5:9311
    
    [secretstore]
    enabled_secretstore_plugins = store_crypto
    
    [crypto]
    enabled_crypto_plugins = simple_crypto
    
    [simple_crypto_plugin]
    kek = ZUkIteiiW5kT57Gh2zUlw88TzKkGkm-GnBK32V1o66g=
    
    [keystone_authtoken]
    auth_uri = http://172.20.10.5:5000
    auth_url = http://172.20.10.5:5000
    memcached_servers = 172.20.10.5:11211
    auth_type = password
    project_domain_name = Default
    user_domain_name = Default
    project_name = service
    username = barbican
    password = password

Sauvegarder : Ctrl+O → Entrée → Ctrl+X

---

#### Étape 9 : Lancer l'installation du contrôleur

> ⚠️ Vérifier avant de lancer :
> - L'utilisateur courant est bien `stack` (`whoami`)
> - Le VG Cinder est bien créé (`vgs`)
> - La connectivité réseau est OK (`ping -c 3 172.20.10.6`)

    cd /opt/stack/devstack
    ./stack.sh

> ⏱️ Durée estimée : 30 à 60 minutes selon la connexion internet.
> Les logs sont disponibles dans : /opt/stack/logs/stack.sh.log

---

#### Étape 8 : Vérification post-installation du contrôleur

    source /opt/stack/devstack/openrc admin admin
    openstack service list          # liste tous les services enregistrés
    openstack compute service list  # vérifie Nova
    openstack network agent list    # vérifie Neutron
    openstack volume service list   # vérifie Cinder

> ✅ Tous les services doivent apparaître en état `up` ou `enabled`.

Interface web Horizon accessible sur :

    http://172.20.10.3/dashboard
    Utilisateur : admin
    Mot de passe : password



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


