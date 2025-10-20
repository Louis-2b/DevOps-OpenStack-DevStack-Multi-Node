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

# --- Déploiement du service Grafana DGFIP sur OpenStack ---
# Ce module met en place :
#   - 3 groupes de sécurité (admin, public, data)
#   - Une instance OpenStack configurée pour Grafana
# Les versions de modules sont figées pour assurer la reproductibilité des déploiements.


# --- Instance principale Grafana ---
module "dgfip_grafana" {
  # Source du module standard DGFIP (création d’instances OpenStack)
  source = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/calcul/terraform-openstack-instance.git?ref=v2.3.0"

  # Nom de l’image OpenStack utilisée (ex : RockyLinux, Debian, etc.)
  # 💡 Paramétrée via variable pour changer facilement selon l’environnement.
  image_name = var.image_name

  # Nombre d’instances Grafana à déployer (généralement 1)
  server_count = 1

  # Préfixe projet / plateforme et phase (ex : a2c-prod, pnm-dev)
  pf_prefixe = var.pf_prefixe
  phase      = var.phase

  # Type logique du serveur (ex : grafana, dashboard, etc.)
  server_type = var.group_grafana

  # Type de machine (CPU/RAM) OpenStack
  # 🧮 À ajuster selon le nombre de dashboards et la charge utilisateur.
  flavor_name = var.grafana_flavor_name

  # Paire de clés SSH pour accès administrateur
  # 🔐 À générer hors du code Terraform.
  key_pair = var.key_pair


  # --- Réseaux associés ---
  admin_network_id = data.openstack_networking_network_v2.admin_network.id
  pub_network_id   = data.openstack_networking_network_v2.pub_network.id
  data_network_id  = data.openstack_networking_network_v2.data_network.id

  # Connexions activées sur les réseaux
  # 🧭 Grafana accède à la data, est publié et administrable.
  is_admin_network = true
  is_pub_network   = true
  is_data_network  = true


  # --- Groupes de sécurité associés ---
  # Séparation stricte entre réseaux : administration / publication / data
  admin_secgroup_id = [module.dgfip_network_secgroup_grafana_admin.secgroup_id]
  pub_secgroup_id   = [module.dgfip_network_secgroup_grafana_pub.secgroup_id]
  data_secgroup_id  = [module.dgfip_network_secgroup_grafana_data.secgroup_id]

  # Aucun groupe supplémentaire manuel (placeholder vide)
  secgroup_name = []


  # --- Disques et redondance ---
  # Disques additionnels (ex : stockage de dashboards persistants, logs)
  extra_disks = var.grafana_extra_disks

  # Groupes de serveurs par zones de disponibilité pour tolérance aux pannes
  servergroup_az1_id = var.servergroup_az1_id
  servergroup_az2_id = var.servergroup_az2_id


  # --- Métadonnées pour inventaire et supervision ---
  metadata = {
    group      = var.group_grafana
    pf_prefixe = var.pf_prefixe
    phase      = var.phase
  }
}


# --- Groupe de sécurité ADMIN ---
module "dgfip_network_secgroup_grafana_admin" {
  # Module DGFIP pour la création des security groups OpenStack
  source = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/networking/terraform-openstack-secgroup.git?ref=v1.0.4"

  pf_prefixe           = var.pf_prefixe
  phase                = var.phase
  sg_objet             = "admin-${var.group_grafana}"
  sg_description       = var.admin_sg_description
  sg_rules             = var.admin_sg_grafana_rules
  delete_default_rules = var.delete_default_rules
}


# --- Groupe de sécurité PUBLIC ---
module "dgfip_network_secgroup_grafana_pub" {
  source = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/networking/terraform-openstack-secgroup.git?ref=v1.0.4"

  pf_prefixe           = var.pf_prefixe
  phase                = var.phase
  sg_objet             = "pub-${var.group_grafana}"
  sg_description       = var.pub_sg_description
  sg_rules             = var.pub_sg_grafana_rules
  delete_default_rules = var.delete_default_rules
}


# --- Groupe de sécurité DATA ---
module "dgfip_network_secgroup_grafana_data" {
  source = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/networking/terraform-openstack-secgroup.git?ref=v1.0.4"

  pf_prefixe           = var.pf_prefixe
  phase                = var.phase
  sg_objet             = "data-${var.group_grafana}"
  sg_description       = var.data_sg_description
  sg_rules             = var.data_sg_grafana_rules
  delete_default_rules = var.delete_default_rules
}
