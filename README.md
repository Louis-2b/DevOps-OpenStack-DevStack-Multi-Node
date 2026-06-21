# Déploiement OpenStack avec Kolla Ansible | Haute disponibilité

<p align="center">
  <img src="Images/Openstack_Logo.jpeg" alt="OpenStack Logo" width="500"/>
</p>

---
## Présentation
> Ce projet documente le processus complet de déploiement d'un environnement **cloud OpenStack à haute disponibilité (HA)** à l'aide de **Kolla-Ansible**. Le déploiement comprend :
> - Configuration multi-nœuds (controller, compute, storage et network)
> - Conteneurisation complète avec Docker
> - Cluster Galera , HAProxy et Keepalived pour la haute disponibilité
> - Configuration centralisée via Ansible
> - Machines virtuelles provisionnées avec KVM/QEMU
>
> Ce guide s'adresse aux ingénieurs DevOps, aux architectes cloud et aux administrateurs système avancés. Il détaille les procédures permettant de reproduire ce déploiement aussi bien en environnement de laboratoire qu'en production.

---
**Environnement de test:**  
> - 🖥️ OS: Rocky Linux 10.2 (ISO minimal)
> - ☁️ Plateforme cloud: OpenStack `2024.2`  
> - ⚙️ Outils: Kolla-Ansible, Docker, Ansible

> **Remarque :** Cette documentation suppose une connaissance de base de **Linux**, **Réseaux** et **Ansible**.

---
## Environment Overview

- Le déploiement a été réalisé dans un laboratoire virtualisé sous VMware Workstation. 
- Une machine virtuelle de base a été créée, puis clonée pour produire des nœuds supplémentaires, chacun se voyant attribuer le rôle qui lui est dévolu.
- Toutes les machines virtuelles fonctionnent sous **Rocky Linux 10.2 (ISO minimal)** et partagent, à l'origine, les mêmes spécifications matérielles, lesquelles sont ensuite adaptées en fonction du rôle assigné à chaque nœud.

> **Télécharger l'ISO de Rocky Linux 10.2 (ISO minimal)**:  
> [https://rockylinux.org/download](https://rockylinux.org/download)

---
## Rôles des nœuds

Cette section décrit les responsabilités spécifiques et les services clés hébergés sur chaque type de nœud au sein du cluster HA OpenStack.


### Contrôleurs (controller01, 02, 03)
Les nœuds de contrôle sont le **"cerveau"** du cloud OpenStack.

| Service | Description |
|---------|-------------|
| `Keystone` | Gestion des identités et authentification |
| `Glance` | Catalogue d'images (stockage local sur /mnt/glance) |
| `Nova API/Scheduler/Conductor` | Gestion des ressources de calcul |
| `Neutron Server` | API réseau |
| `Horizon` | Interface web Dashboard |
| `MariaDB (Galera)` | Base de données en cluster HA |
| `RabbitMQ` | File d'attente de messages (HA) |
| `Memcached` | Cache de sessions |
| `HAProxy + Keepalived` | Équilibrage de charge haute disponibilité |
| `Prometheus + Grafana` | Monitoring et métriques |

> ⚠️ **IMPORTANT** : En architecture HA, les contrôleurs doivent être en nombre impair (3, 5, etc.) pour le quorum MariaDB.

### Réseau (network01)
Le nœud réseau gère toute la connectivité réseau des instances.

| Service | Description |
|---------|-------------|
| `Neutron OpenvSwitch Agent` | Gestion des réseaux overlay (VXLAN/GRE) |
| `Neutron L3 Agent` | Routage entre réseaux (NAT) |
| `Neutron DHCP Agent` | Attribution d'adresses IP aux instances |
| `Neutron Metadata Agent` | Fournit des métadonnées aux instances |
| `OVN` | Contrôleur SDN (optionnel selon configuration) |

### Calcul (compute01)
Les nœuds de calcul exécutent les machines virtuelles.

| Service | Description |
|---------|-------------|
| `Nova Compute` | Gestion du cycle de vie des VMs |
| `Libvirt/KVM` | Hyperviseur pour l'exécution des VMs |
| `Neutron OpenvSwitch Agent` | Connectivité réseau pour les VMs |
| `Ceilometer Compute` | Collecte de métriques au niveau du compute |
| `Prometheus Node Exporter` | Monitoring des ressources du nœud |

### Stockage (storage01)
Le nœud de stockage fournit du stockage persistant.

| Service | Description |
|---------|-------------|
| `Cinder Volume` | Gestion des volumes (stockage bloc) |
| `Cinder Backup` | Sauvegarde des volumes (optionnel) |
| `LVM` | Gestion des volumes logiques pour Cinder |
| `iscsid / tgtd` | Services iSCSI pour les volumes Cinder |
| `Prometheus Node Exporter` | Monitoring des ressources du nœud |

---

## Services déployés

### Services core
| Service | Statut | Description |
|---------|--------|-------------|
| ✅ **Keystone** | Activé | Authentification et identité |
| ✅ **Glance** | Activé | Catalogue d'images |
| ✅ **Nova** | Activé | Service de calcul |
| ✅ **Neutron** | Activé | Service réseau |
| ✅ **Horizon** | Activé | Dashboard web |
| ✅ **Heat** | Activé | Orchestration |
| ✅ **Cinder** | Activé | Stockage bloc (LVM) |

### Monitoring & Télémétrie
| Service | Statut | Description |
|---------|--------|-------------|
| ✅ **Prometheus** | Activé | Collecte de métriques |
| ✅ **Grafana** | Activé | Visualisation des métriques |
| ✅ **Ceilometer** | Activé | Collecte des données de téléchargement |
| ✅ **Aodh** | Activé | Alerte et alarmes |
| ✅ **Gnocchi** | Activé | Stockage des métriques (backend file) |

### Services avancés
| Service | Statut | Description |
|---------|--------|-------------|
| ✅ **Zun** | Activé | Gestion des conteneurs |
| ✅ **Kuryr** | Activé | Intégration réseau pour les conteneurs |
| ✅ **Designate** | Activé | Service DNS (Domain Name System) |
| ✅ **Barbican** | Activé | Gestion des secrets |
| ✅ **Octavia** | Activé | Équilibrage de charge |
| ✅ **Magnum** | Activé | Orchestration de conteneurs (Kubernetes) |

---

## Deployment Architecture

Cette section décrit l'architecture du déploiement OpenStack HA, y compris les rôles attribués à chaque nœud, leurs spécifications matérielles et la manière dont ils sont organisés pour garantir l'évolutivité, la haute disponibilité et la séparation des préoccupations.


| Nom d'hôte   | Rôle                 | IPv4            | vCPU | RAM (GB) | Storage (GB)  | Notes                       |
|--------------|----------------------|-----------------|------|----------|---------------|-----------------------------|
| controller01 | Nœud de control      | 172.20.10.2     | 8    | 24       | 150-200       | Utilisé pour déployer Kolla |
| controller02 | Nœud de control      | 172.20.10.3     | 8    | 24       | 150-200       |                             |
| controller03 | Nœud de control      | 172.20.10.5     | 8    | 24       | 150-200       |                             |
| compute01    | Nœud de calcul       | 172.20.10.6     | 4    | 16       | 100           | La virtualisation activée   |
| network01    | Nœud de réseau       | 172.20.10.7     | 4    | 16       | 80            |                             |
| storage01    | Stockage (Cinder LVM)| 172.20.10.8     | 4    | 8        | 100 (+100 GB) | Volume LVM pour Cinder      |

> **Remarque :** chaque machine virtuelle a été clonée à partir de la VM de base **controller01**, puis personnalisée individuellement (nom d'hôte, adresse IP statique, configuration des cartes réseau, etc.).
---

## Réseau de machines virtuelles

Chaque machine virtuelle comprend au moins deux interfaces réseau :

- `ens160`: Réseau de gestion interne/OpenStack
- `ens192`: Réseau externe pour les adresses IP flottantes et l'accès externe
  
Les noms des cartes réseau peuvent varier en fonction de la configuration de l'hyperviseur.

> ⚠️ **Rappel :** Veuillez toujours vérifier les noms des cartes réseau `ip a` après la création de la machine virtuelle.

---
### 🖥️ Création et Installation de la Machine Virtuelle Rocky Linux de Base

Cette étape consiste à créer une **machine virtuelle de référence** (`controller01`) qui servira de base pour cloner tous les autres nœuds du cluster (contrôleurs, compute, network, storage, etc.).

#### 1. Création de la machine virtuelle

1. Créez une nouvelle machine virtuelle nommée **`controller01`**.
2. Configurez les ressources matérielles suivantes (à adapter selon votre infrastructure) :
   - **vCPU** : 2 (minimum) – 4 recommandés pour un contrôleur
   - **Mémoire RAM** : 8 Go (minimum) – 16 Go recommandés
   - **Disque dur** : 40 Go (minimum) – 60 Go+ recommandés en production
   - **Type de disque** : Thin Provision (pour économiser l’espace)

   ![Spécifications de la VM](Images/Pic-01.png)

3. **Ajoutez une deuxième carte réseau (NIC)** pour séparer les réseaux interne et externe :
   - NIC 1 → Réseau de management / API (ens160)
   - NIC 2 → Réseau externe / Provider networks (ens192)

   ![Ajout carte réseau 1](Images/Pic-02.png)
   ![Ajout carte réseau 2](Images/Pic-03.png)
   ![Configuration finale des NIC](Images/Pic-04.png)

4. Vérifiez le résumé de la configuration avant de valider.

   ![Résumé final](images/pic5.png)

#### 2. Installation de Rocky Linux 9.4

1. Démarrez la machine virtuelle et lancez l’installation de **Rocky Linux 9.4**.

   ![Démarrage de l’installation](images/pic6.png)

2. Sélectionnez la langue d’installation (recommandé : **Français**).

   ![Choix de la langue](images/pic7.png)

3. Configurez les paramètres d’installation :

   - **Partitionnement** : Utilisez le partitionnement automatique ou manuel (LVM recommandé).
   - **Réseau et nom d’hôte**
   - **Fuseau horaire**
   - **Utilisateur root** (mot de passe fort)
   - **Création d’un utilisateur standard**

   ![Écran de configuration](images/pic8.png)

#### 3. Configuration critique de l’utilisateur et du réseau

- **Utilisateur Kolla** :  
  Créez un utilisateur nommé **`kolla`** avec des droits `sudo` (sans mot de passe recommandé pour l’automatisation).  
  Cet utilisateur sera utilisé pour exécuter Kolla-Ansible.

- **Configuration réseau** (très important) :
  - **NIC 1 (ens160)** : Laissez **DHCP activé** (vous configurerez une IP statique plus tard via cloud-init ou NetworkManager).
  - **NIC 2 (ens192)** :  
    - Désactivez **IPv4** (cette interface sera utilisée plus tard pour les réseaux providers Neutron).
    - Désactivez puis réactivez l’interface pour appliquer les changements.

   ![Configuration réseau NIC 1](images/pic9.png)
   ![Configuration réseau NIC 2](images/pic10.png)
   ![Activation de la carte](images/pic11.png)

4. Validez toutes les configurations et lancez l’installation.

   ![Lancement de l’installation](images/pic12.png)

---

### ✅ Bonnes pratiques recommandées

- **Nommez clairement vos VMs** : `controller01`, `controller02`, `compute01`, etc.
- **Utilisez des snapshots** après l’installation propre de la VM de base.
- **Désactivez SELinux en mode permissive** pendant la phase de test (vous pourrez le remettre en enforcing plus tard).
- **Mettez à jour le système** immédiatement après la première connexion :
  ```bash
  sudo dnf update -y
  sudo reboot
  ```

- **Configurez SSH sans mot de passe** entre les nœuds dès le début.

---

**Prêt à être intégré** dans votre README global.

Souhaitez-vous que je continue avec la section suivante (ex. : Configuration post-installation du nœud `controller01`, configuration réseau statique, installation de Kolla-Ansible, etc.) ?
