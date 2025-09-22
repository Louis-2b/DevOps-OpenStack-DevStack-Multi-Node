# Déploiement OpenStack avec DevStack

Ce guide documente les étapes complètes pour préparer un serveur, installer et déployer OpenStack en utilisant **DevStack** sur un **OS DEBIAN 12**.

## Prérequis généraux

### Matériel :

Minimum **2 machines (1 contrôleur + 1 compute)**.
Chaque machine doit avoir au moins **10 Go de RAM ou plus**, **8 cœurs CPU ou plus**, deux espace disque sur la machine contrôleur et un espace disque sur la machine compute  **(100 Go recommandé ou plus)** et deux cartes réseaux en mode **Bridged**.
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

# Adresse IP du nœud contrôleur (celle de ta machine sur le LAN)
HOST_IP=192.168.1.121

# Plage réseau interne pour les instances (ne doit pas entrer en conflit avec ton LAN)
FIXED_RANGE=10.0.1.0/20

# Plage d’adresses IP flottantes (doit appartenir au même réseau que HOST_IP)
FLOATING_RANGE=192.168.1.120/25

# interface reliée au LAN externe (pas d’IP assignée directement)
PUBLIC_INTERFACE=ens34

# utilisée par Neutron pour le réseau provider
FLAT_INTERFACE=ens34

# Emplacement du fichier de logs
LOGFILE=/opt/stack/logs/stack.sh.log

# Configuration multi-nœud
MULTI_HOST=1

# Mot de passe admin
ADMIN_PASSWORD=adminuser

# Mot de passe DB
DATABASE_PASSWORD=labstack

# Mot de passe RabbitMQ
RABBIT_PASSWORD=labstack

# Mot de passe services
SERVICE_PASSWORD=labstack

# Activer les services Cinder
enable_service c-api c-vol c-sch c-bak

# Configurer le backend LVM pour Cinder
CINDER_ENABLED_BACKENDS=lvm:lvmdriver-1
VOLUME_GROUP="cinder-volumes"
VOLUME_BACKING_FILE_SIZE=50000M


# Désactiver les services qui ne doivent pas tourner sur le contrôleur
disable_service n-cpu q-agt tempest
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

# Adresse IP du nœud compute (celle de ta machine sur le LAN)
HOST_IP=192.168.1.41

# Plage réseau interne pour les instances (ne doit pas entrer en conflit avec ton LAN)
FIXED_RANGE=10.0.1.0/24

# Plage d’adresses IP flottantes (doit appartenir au même réseau que HOST_IP)
FLOATING_RANGE=192.168.1.120/24

# Emplacement du fichier de logs
LOGFILE=/opt/stack/logs/stack.sh.log

# Mots de passe (doivent correspondre à ceux du contrôleur)
ADMIN_PASSWORD=adminuser
DATABASE_PASSWORD=labstack
RABBIT_PASSWORD=labstack
SERVICE_PASSWORD=labstack

# Type de base de données
DATABASE_TYPE=mysql

# Adresse IP du nœud contrôleur
SERVICE_HOST=192.168.1.50

# Hôtes des services centraux (sur le contrôleur)
MYSQL_HOST=$SERVICE_HOST
RABBIT_HOST=$SERVICE_HOST
GLANCE_HOSTPORT=$SERVICE_HOST:9292

# Services activés sur le nœud compute
ENABLED_SERVICES=n-cpu,c-vol,placement-client,ovn-controller,ovs-vswitchd,ovsdb-server,q-ovn-metadata-agent

# Configuration VNC pour console
NOVA_VNC_ENABLED=True
NOVNCPROXY_URL="http://$SERVICE_HOST:6080/vnc_lite.html"
VNCSERVER_LISTEN=$HOST_IP
VNCSERVER_PROXYCLIENT_ADDRESS=$VNCSERVER_LISTEN

# Désactiver les services qui ne doivent pas tourner sur compute
disable_service tempest
```

