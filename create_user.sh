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

# Module Terraform pour déployer un bastion DGFIP sur OpenStack.
# Ce module est versionné (ref=v2.1.1) pour garantir la reproductibilité.
# ⚠️ Toujours fixer la version du module pour éviter les changements inattendus.

module "dgfip_bastion_outillage" {
  # Source du module : dépôt Git interne DGFIP avec version figée
  source = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/s-curit/terraform-openstack-bastion.git?ref=v2.1.1"

  # Nom de l'image (système d’exploitation) utilisée pour le bastion.
  # ⚙️ À paramétrer via une variable pour faciliter le changement d’image selon l’environnement.
  image_name = var.image_name

  # Préfixe du projet ou de la plateforme.
  # 🧱 Permet de distinguer les environnements (ex : pf_prefixe = "a2c-dev", "a2c-prod", etc.)
  pf_prefixe = var.pf_prefixe

  # Phase du déploiement (ex : dev, recette, prod)
  # 🧩 Facilite la gestion des ressources multi-environnements.
  phase = var.phase

  # Type de machine OpenStack (CPU/RAM)
  # 💡 Choisir des flavors adaptés à la charge attendue.
  flavor_name = var.bastion_flavor_name

  # Paire de clés SSH autorisée pour l’accès administrateur au bastion
  # 🔐 À générer et gérer en dehors du module pour éviter de stocker des clés dans le code.
  key_pair = var.key_pair

  # Réseau d’administration interne où le bastion sera connecté
  admin_network_id = data.openstack_networking_network_v2.admin_network.id

  # Pool d’adresses IP flottantes pour l’accès externe (public)
  admin_floating_ip_pool = var.admin_external_network_name

  # IP flottante fixe à réutiliser (si existante)
  # 🧭 Permet la redéployabilité sans changer d’adresse IP.
  admin_fixed_fip = [data.openstack_networking_floatingip_v2.bastion_ip.address]

  # Règles de sécurité spécifiques au bastion
  # 🔒 Définies dans un objet variable pour gérer finement les accès (SSH, ICMP, etc.)
  admin_sg_bastion_rules = var.admin_sg_bastion_rules
}
