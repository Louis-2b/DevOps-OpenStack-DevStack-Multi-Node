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

# --- Module Terraform pour déployer un HAProxy DGFIP sur OpenStack ----
# Ce module installe et configure une ou plusieurs instances HAProxy
# en respectant les standards DGFIP d'infrastructure et de sécurité.
# Version du module figée pour garantir la reproductibilité et la traçabilité des déploiements.

module "dgfip_haproxy_outillage" {
  # Source du module : dépôt Git interne DGFIP avec version explicitement figée
  # 🔒 Fixer la version évite les modifications involontaires dues à des mises à jour du module.
  source = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/networking/terraform-openstack-haproxy.git?ref=v2.3.0"

  # --- Paramètres d'image et d’environnement ---

  # Nom de l'image (OS) utilisée pour l'instance HAProxy.
  # 💡 Paramétrée par variable pour gérer différents environnements (ex : Debian, Rocky, Ubuntu).
  image_name = var.haproxy_image_name

  # Préfixe du projet / plateforme
  # 🧩 Permet d’identifier facilement les ressources liées à un environnement (ex : a2c-dev, a2c-prod).
  pf_prefixe = var.pf_prefixe

  # Phase de déploiement (ex : dev, recette, prod)
  # 🧱 Sert à isoler les environnements et à gérer le cycle de vie des déploiements.
  phase = var.phase


  # --- Configuration de la machine ---

  # Nombre d'instances HAProxy à déployer.
  # ⚙️ Utile pour le scaling et la haute disponibilité (actif/passif ou actif/actif).
  server_count = var.haproxy_server_count

  # Type de machine (flavor OpenStack)
  # 🧮 Adapter en fonction de la charge et du trafic attendu.
  flavor_name = var.haproxy_flavor_name

  # Paire de clés SSH autorisée pour l’administration du HAProxy.
  # 🔐 Toujours générer et gérer cette clé hors du dépôt Terraform.
  key_pair = var.key_pair


  # --- Réseaux et sécurité ---

  # Réseau interne d’administration (back-end, supervision, SSH)
  admin_network_id = data.openstack_networking_network_v2.admin_network.id

  # Règles de sécurité spécifiques au HAProxy
  # 🔒 Gérer ces règles via des variables pour les adapter à chaque environnement.
  admin_sg_haproxy_rules = var.admin_sg_haproxy_rules

  # Réseau public de publication (front-end)
  pub_network_id = data.openstack_networking_network_v2.pub_network.id

  # Pool d’adresses IP flottantes pour la publication externe.
  # 🌐 Fournit l’accès depuis l’extérieur du réseau administratif.
  publication_floating_ip_pool = var.pub_external_network_name

  # Adresse IP flottante fixe (si existante)
  # 🧭 Garantit la stabilité réseau entre déploiements.
  publication_fixed_fip = [data.openstack_networking_floatingip_v2.haproxy_ip.address]


  # --- Haute disponibilité et stockage ---

  # Groupes de serveurs pour les zones de disponibilité (AZ)
  # 🧠 Permet de répartir les instances HAProxy sur plusieurs AZ pour tolérance de panne.
  servergroup_az1_id = var.servergroup_az1_id
  servergroup_az2_id = var.servergroup_az2_id

  # Adresses IP virtuelles publiques (VIPs)
  # 🎯 Utilisées pour le failover ou le load balancing entre les instances HAProxy.
  vips_pub = var.haproxy_vips_pub

  # Disques additionnels (optionnels)
  # 💾 Peut servir pour la journalisation, la configuration ou le stockage temporaire.
  extra_disks = var.haproxy_extra_disks
}
