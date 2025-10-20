#!/bin/bash
. /home/alcapone/devstack/openrc admin admin

# Créer utilisateur diegosoda
NAME=diegosoda
PASSWORD=adminuser
PROJECT=kubernetes
openstack project create $PROJECT
openstack user create $NAME --password=$PASSWORD --project $PROJECT
openstack role add admin --user $NAME --project $PROJECT

# Créer utilisateur tubie
NAME=tubie
PASSWORD=adminuser
PROJECT=infras
openstack project create $PROJECT
openstack user create $NAME --password=$PASSWORD --project $PROJECT
openstack role add member --user $NAME --project $PROJECT

# Créer utilisateur alcapone
NAME=alcapone
PASSWORD=adminuser
PROJECT=gitlab
openstack project create $PROJECT
openstack user create $NAME --password=$PASSWORD --project $PROJECT
openstack role add admin --user $NAME --project $PROJECT

############################################################################################################

# --- Modules Terraform pour le déploiement du Monitoring DGFIP sur OpenStack ---
# Ce code crée les groupes de sécurité (admin et public) et déploie ensuite l’instance de monitoring
# en appliquant les règles de sécurité et la configuration réseau adaptée.
# Toutes les versions de modules sont figées pour garantir la reproductibilité.

# --- Groupe de sécurité ADMIN pour le monitoring ---
module "dgfip_network_secgroup_monitoring_admin" {
  # Source du module : module standard DGFIP de gestion des security groups
  source = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/networking/terraform-openstack-secgroup.git?ref=v1.0.4"

  # Préfixe de la plateforme (ex : a2c, pnm, etc.)
  # 🧩 Permet d’isoler les ressources par environnement
  pf_prefixe = var.pf_prefixe

  # Phase du déploiement (dev, recette, prod)
  # 🧱 Utile pour distinguer les environnements
  phase = var.phase

  # Nom logique du groupe de sécurité (concaténé avec “admin-”)
  # 💡 Facilite l’identification des règles côté OpenStack
  sg_objet = "admin-${var.monitoring_group_name}"

  # Description textuelle du SG
  sg_description = var.admin_sg_description

  # Règles de sécurité appliquées au réseau admin
  # 🔒 Par exemple : SSH depuis bastion, ICMP, accès interne à Prometheus/Grafana
  sg_rules = var.admin_sg_monitoring_rules

  # Suppression des règles par défaut
  # 🚫 Active une politique “zéro trust” avant ajout des règles explicites
  delete_default_rules = var.delete_default_rules
}


# --- Groupe de sécurité PUBLIC pour le monitoring ---
module "dgfip_network_secgroup_monitoring_pub" {
  # Module identique au précédent mais pour le réseau public
  source = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/networking/terraform-openstack-secgroup.git?ref=v1.0.4"

  pf_prefixe           = var.pf_prefixe
  phase                = var.phase
  sg_objet             = "pub-${var.monitoring_group_name}"
  sg_description       = var.pub_sg_description
  sg_rules             = var.pub_sg_monitoring_rules
  delete_default_rules = var.delete_default_rules
}


# --- Déploiement de l’instance de Monitoring (Prometheus / Grafana / Loki, etc.) ---
module "dgfip_monitoring_outillage" {
  # Module de création d’instance OpenStack standardisé DGFIP
  source = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/calcul/terraform-openstack-instance.git?ref=v2.3.0"

  # Nom de l'image (ex : Debian 12 Hardened)
  image_name = var.image_name

  # Type de serveur logique (ex : monitoring, grafana, prometheus)
  server_type = var.monitoring_group_name

  # Préfixe projet et phase de déploiement
  pf_prefixe = var.pf_prefixe
  phase      = var.phase

  # Type de machine (CPU/RAM)
  flavor_name = var.monitoring_flavor_name

  # Paire de clés SSH autorisée pour l’administration
  # 🔐 Toujours gérée hors du code Terraform pour des raisons de sécurité
  key_pair = var.key_pair


  # --- Configuration réseau ---
  admin_network_id = data.openstack_networking_network_v2.admin_network.id
  pub_network_id   = data.openstack_networking_network_v2.pub_network.id
  data_network_id  = data.openstack_networking_network_v2.data_network.id

  # Indique sur quels réseaux connecter l’instance
  # 🧭 Utile pour isoler la data, l’administration et la publication
  is_admin_network = true
  is_pub_network   = true
  is_data_network  = false

  # Pool d’adresses IP flottantes du réseau admin
  admin_floating_ip_pool = var.admin_external_network_name

  # Association des groupes de sécurité précédemment créés
  # 🔒 Sépare clairement les accès internes (admin) et externes (pub)
  admin_secgroup_id = [module.dgfip_network_secgroup_monitoring_admin.secgroup_id]
  pub_secgroup_id   = [module.dgfip_network_secgroup_monitoring_pub.secgroup_id]


  # --- Stockage et haute disponibilité ---
  extra_disks = var.monitoring_extra_disks

  # Groupes de serveurs dans les zones de disponibilité (AZ1 / AZ2)
  # 🧠 Assure la redondance du service en cas de panne d’une zone
  servergroup_az1_id = var.servergroup_az1_id
  servergroup_az2_id = var.servergroup_az2_id

  # Métadonnées pour l’inventaire et la supervision
  metadata = {
    group      = var.monitoring_group_name
    pf_prefixe = var.pf_prefixe
    phase      = var.phase
  }
}

