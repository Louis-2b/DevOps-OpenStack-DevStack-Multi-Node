# Déploiement OpenStack avec DevStack

Ce guide documente les étapes complètes pour préparer un serveur, installer et déployer OpenStack en utilisant **DevStack** sur un **OS DEBIAN 12**.

## Prérequis généraux

### Matériel :

Minimum **2 machines (1 contrôleur + 1 compute)**.
Chaque machine doit avoir au moins **10 Go de RAM**, **8 cœurs CPU**, et un espace disque suffisant **(100 Go recommandé)**.
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
    address 192.168.1.50/24
    gateway 192.168.1.254
    dns-nameservers 8.8.8.8 8.8.4.4
```

Redémarrer :

```bash
# Appliquer la nouvelle configuration
sudo systemctl restart networking
```

## 3. SSH (A faire sur la machine contrôleur)
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

### Téléchargement de DevStack

```bash
git clone https://opendev.org/openstack/devstack
cd devstack
```


# Étapes d’installation

## 1. Configuration du nœud contrôleur
Le nœud contrôleur exécute les services principaux d’OpenStack (API, Keystone, Nova Scheduler, Neutron, etc.).

### Créer le fichier de configuration local.conf

```bash
nano local.conf


[[local|localrc]]

# Adresse IP du nœud contrôleur (celle de ta machine sur le LAN)
HOST_IP=192.168.1.50

# Plage réseau interne pour les instances (ne doit pas entrer en conflit avec ton LAN)
FIXED_RANGE=10.0.1.0/24

# Plage d’adresses IP flottantes (doit appartenir au même réseau que HOST_IP)
FLOATING_RANGE=192.168.1.120/24

# Emplacement du fichier de logs
LOGFILE=/opt/stack/logs/stack.sh.log

# Mot de passe admin
ADMIN_PASSWORD=< VOTRE_MOT_DE_PASSE >

# Mot de passe DB
DATABASE_PASSWORD=< VOTRE_MOT_DE_PASSE >

# Mot de passe RabbitMQ
RABBIT_PASSWORD=< VOTRE_MOT_DE_PASSE >

# Mot de passe services
SERVICE_PASSWORD=< VOTRE_MOT_DE_PASSE >
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
```