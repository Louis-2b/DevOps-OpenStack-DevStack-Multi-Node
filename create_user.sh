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

module "dgfip_bastion_outillage" {
  source                 = "git::https://forge.dgfip.finances.rie.gouv.fr/dgfip/si1/dan-a2c/module-terraform-dgfip/s-curit/terraform-openstack-bastion.git?ref=v2.1.1"
  image_name             = var.image_name
  pf_prefixe             = var.pf_prefixe
  phase                  = var.phase
  flavor_name            = var.bastion_flavor_name
  key_pair               = var.key_pair
  admin_network_id       = data.openstack_networking_network_v2.admin_network.id
  admin_floating_ip_pool = var.admin_external_network_name
  admin_fixed_fip        = [data.openstack_networking_floatingip_v2.bastion_ip.address]
  admin_sg_bastion_rules = var.admin_sg_bastion_rules
}
