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

module "dgfip_grafana" {
  source             = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/calcul/terraform-openstack-instance.git?ref=v2.3.0"
  image_name         = var.image_name
  server_count       = 1
  pf_prefixe         = var.pf_prefixe
  phase              = var.phase
  server_type        = var.group_grafana
  flavor_name        = var.grafana_flavor_name
  key_pair           = var.key_pair
  admin_network_id   = data.openstack_networking_network_v2.admin_network.id
  pub_network_id     = data.openstack_networking_network_v2.pub_network.id
  data_network_id    = data.openstack_networking_network_v2.data_network.id
  is_admin_network   = true
  is_pub_network     = true
  is_data_network    = true
  admin_secgroup_id  = [module.dgfip_network_secgroup_grafana_admin.secgroup_id]
  pub_secgroup_id    = [module.dgfip_network_secgroup_grafana_pub.secgroup_id]
  data_secgroup_id   = [module.dgfip_network_secgroup_grafana_data.secgroup_id]
  secgroup_name      = []
  extra_disks        = var.grafana_extra_disks
  servergroup_az1_id = var.servergroup_az1_id
  servergroup_az2_id = var.servergroup_az2_id
  metadata = {
    group      = var.group_grafana
    pf_prefixe = var.pf_prefixe
    phase      = var.phase
  }
}
module "dgfip_network_secgroup_grafana_admin" {
  source               = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/networking/terraform-openstack-secgroup.git?ref=v1.0.4"
  pf_prefixe           = var.pf_prefixe
  phase                = var.phase
  sg_objet             = "admin-${var.group_grafana}"
  sg_description       = var.admin_sg_description
  sg_rules             = var.admin_sg_grafana_rules
  delete_default_rules = var.delete_default_rules
}

module "dgfip_network_secgroup_grafana_pub" {
  source               = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/networking/terraform-openstack-secgroup.git?ref=v1.0.4"
  pf_prefixe           = var.pf_prefixe
  phase                = var.phase
  sg_objet             = "pub-${var.group_grafana}"
  sg_description       = var.pub_sg_description
  sg_rules             = var.pub_sg_grafana_rules
  delete_default_rules = var.delete_default_rules
}

module "dgfip_network_secgroup_grafana_data" {
  source               = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/networking/terraform-openstack-secgroup.git?ref=v1.0.4"
  pf_prefixe           = var.pf_prefixe
  phase                = var.phase
  sg_objet             = "data-${var.group_grafana}"
  sg_description       = var.data_sg_description
  sg_rules             = var.data_sg_grafana_rules
  delete_default_rules = var.delete_default_rules
}
