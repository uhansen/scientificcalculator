locals {
  use_existing_cluster_id   = trimspace(var.existing_cluster_id) != ""
  use_existing_cluster_name = trimspace(var.existing_cluster_name) != ""
  create_cluster            = !local.use_existing_cluster_id && !local.use_existing_cluster_name
  node_pool_name            = trimspace(var.node_pool_name) != "" ? var.node_pool_name : "${var.cluster_name}-pool"
  cluster_name_resolved = local.use_existing_cluster_name ? data.opentelekomcloud_cce_cluster_v3.existing[0].name : (
    local.use_existing_cluster_id ? var.cluster_name : opentelekomcloud_cce_cluster_v3.this[0].name
  )
}

resource "terraform_data" "input_validation" {
  input = true

  lifecycle {
    precondition {
      condition     = !(local.use_existing_cluster_id && local.use_existing_cluster_name)
      error_message = "Set at most one of existing_cluster_id or existing_cluster_name."
    }

    precondition {
      condition     = local.create_cluster || trimspace(var.cluster_name) != ""
      error_message = "cluster_name must be set when creating a new cluster or when reusing by ID."
    }
  }
}

data "opentelekomcloud_cce_cluster_v3" "existing" {
  count  = local.use_existing_cluster_name ? 1 : 0
  name   = var.existing_cluster_name
  status = "Available"

  depends_on = [terraform_data.input_validation]
}

resource "opentelekomcloud_cce_cluster_v3" "this" {
  count = local.create_cluster ? 1 : 0

  name                   = var.cluster_name
  description            = var.cluster_description
  cluster_version        = var.cluster_version
  cluster_type           = "VirtualMachine"
  flavor_id              = var.cluster_flavor
  vpc_id                 = var.vpc_id
  subnet_id              = var.subnet_id
  container_network_type = "overlay_l2"
  authentication_mode    = "rbac"
  kube_proxy_mode        = "ipvs"
  timezone               = var.timezone
  api_access_trustlist   = var.api_access_trustlist

  delete_evs = "try"
  delete_net = "try"

  depends_on = [terraform_data.input_validation]
}

locals {
  cluster_id = local.use_existing_cluster_id ? var.existing_cluster_id : (
    local.use_existing_cluster_name ? data.opentelekomcloud_cce_cluster_v3.existing[0].id : opentelekomcloud_cce_cluster_v3.this[0].id
  )
}

resource "opentelekomcloud_cce_node_pool_v3" "default" {
  count = local.create_cluster ? 1 : 0

  cluster_id         = local.cluster_id
  name               = local.node_pool_name
  os                 = var.node_os
  flavor             = var.node_flavor
  initial_node_count = var.node_count
  availability_zone  = var.availability_zone
  key_pair           = var.ssh_key_name
  subnet_id          = var.subnet_id
  runtime            = "containerd"

  root_volume {
    size       = var.root_volume_size
    volumetype = var.root_volume_type
  }

  data_volumes {
    size       = var.data_volume_size
    volumetype = var.data_volume_type
  }

  depends_on = [opentelekomcloud_cce_cluster_v3.this]
}

data "opentelekomcloud_cce_cluster_kubeconfig_v3" "this" {
  cluster_id = local.cluster_id
  duration   = var.kubeconfig_duration

  depends_on = [
    terraform_data.input_validation,
    opentelekomcloud_cce_cluster_v3.this,
    opentelekomcloud_cce_node_pool_v3.default,
  ]
}
