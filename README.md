# Déploiement OpenStack avec DevStack

Ce guide documente les étapes complètes pour préparer un serveur, installer et déployer OpenStack en utilisant **DevStack** sur un **OS DEBIAN 12**.

## Prérequis généraux

### Matériel :

Minimum **2 machines (1 contrôleur + 1 compute)**.
Chaque machine doit avoir au moins **10 Go de RAM**, **8 cœurs CPU**, et un espace disque suffisant **(100 Go recommandé)**.
Système d'exploitation : **Debian 12**.

---

## 1. Préparation du système
A faire sur les **2 machines (1 contrôleur + 1 compute)**

```bash
su -
apt update -y && apt upgrade -y
apt install sudo -y
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