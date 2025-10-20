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

# --- Module Terraform pour déployer un HAproxy DGFIP sur OpenStack ----


module "dgfip_haproxy_outillage" {
  # Source du module : dépôt Git interne DGFIP avec version figée
  source                       = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/networking/terraform-openstack-haproxy.git?ref=v2.3.0"

  # Nom de l'image (système d’exploitation) utilisée pour le haproxy
  # À paramétrer via une variable pour faciliter le changement d’image selon l’environnement
  image_name                   = var.haproxy_image_name

  # Préfixe du projet ou de la plateforme
  # Permet de distinguer les environnements
  pf_prefixe                   = var.pf_prefixe

  # Phase du déploiement
  # Facilite la gestion des ressources multi-environnements
  phase                        = var.phase


  server_count                 = var.haproxy_server_count

  # Type de machine OpenStack (CPU/RAM)
  # Choisir des flavors adaptés à la charge attendue.
  flavor_name                  = var.haproxy_flavor_name

  # Paire de clés SSH autorisée pour l’accès administrateur au haproxy
  # À générer et gérer en dehors du module pour éviter de stocker des clés dans le code
  key_pair                     = var.key_pair

  # Réseau d’administration interne où le haproxy sera connecté
  admin_network_id             = data.openstack_networking_network_v2.admin_network.id

  # Règles de sécurité spécifiques au haproxy
  # Définies dans un objet variable pour gérer finement les accès (SSH, ICMP, etc.)
  admin_sg_haproxy_rules       = var.admin_sg_haproxy_rules

  
  pub_network_id               = data.openstack_networking_network_v2.pub_network.id
  publication_floating_ip_pool = var.pub_external_network_name
  publication_fixed_fip        = [data.openstack_networking_floatingip_v2.haproxy_ip.address]
  servergroup_az1_id           = var.servergroup_az1_id
  servergroup_az2_id           = var.servergroup_az2_id
  vips_pub                     = var.haproxy_vips_pub
  extra_disks                  = var.haproxy_extra_disks
}
