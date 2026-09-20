variable "app_name" {
  description = "Application name used for SpinApp and routing resources."
  type        = string
  default     = "thecalculatorspin"
}

variable "app_host" {
  description = "Canonical host name expected by the KEDA HTTP interceptor."
  type        = string
}

variable "image" {
  description = "OCI image for the Spin application."
  type        = string
  default     = "ghcr.io/uhansen/thecalculatorspin:latest"
}

variable "ghcr_username" {
  description = "GitHub Container Registry username for pulling the application image."
  type        = string
}

variable "ghcr_token" {
  description = "GitHub Container Registry token for pulling the application image."
  type        = string
  sensitive   = true
}

variable "cert_manager_version" {
  description = "cert-manager Helm chart version."
  type        = string
  default     = "v1.21.1"
}

variable "runtime_class_manager_version" {
  description = "runtime-class-manager Helm chart version."
  type        = string
  default     = "0.2.0"
}

variable "spin_shim_version" {
  description = "Spin shim release version used by runtime-class-manager."
  type        = string
  default     = "v0.25.1"
}

variable "spin_operator_version" {
  description = "spin-operator release version."
  type        = string
  default     = "v0.6.1"
}

variable "keda_version" {
  description = "KEDA Helm chart version."
  type        = string
  default     = "2.20.2"
}

variable "keda_http_addon_version" {
  description = "KEDA HTTP add-on Helm chart version."
  type        = string
  default     = "0.15.0"
}

variable "envoy_gateway_version" {
  description = "Envoy Gateway Helm chart version."
  type        = string
  default     = "v1.9.1"
}

locals {
  charts_dir                          = "${path.module}/charts"
  app_namespace                       = "default"
  cert_manager_namespace              = "cert-manager"
  runtime_class_manager_namespace     = "runtime-class-manager"
  spin_operator_namespace             = "spin-operator"
  keda_namespace                      = "keda"
  envoy_gateway_namespace             = "envoy-gateway-system"
  runtime_class_manager_chart_version = trimprefix(var.runtime_class_manager_version, "v")
  spin_operator_chart_version         = trimprefix(var.spin_operator_version, "v")
  envoy_gateway_release_name          = "envoy-gateway"
  envoy_gateway_class_name            = "${var.app_name}-envoy"
  envoy_gateway_name                  = "${var.app_name}-http"
  envoy_proxy_name                    = "${var.app_name}-envoyproxy"
  keda_http_release_name              = "keda-add-ons-http"
  keda_http_interceptor_proxy_service = "keda-add-ons-http-interceptor-proxy"
  ghcr_pull_secret_name               = "ghcr-pull-secret"

  # AKS's built-in cloud provider provisions a Standard SKU Azure Load
  # Balancer automatically for a Service type=LoadBalancer, so these
  # annotations only customize it - no separate load-balancer controller is
  # installed or required (unlike the AWS Load Balancer Controller on EKS).
  envoy_lb_annotations = {
    "service.beta.kubernetes.io/azure-load-balancer-internal" = "false"
  }
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = local.cert_manager_namespace
  create_namespace = true
  repository       = "oci://quay.io/jetstack/charts"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  timeout          = 600

  values = [yamlencode({
    installCRDs = true
  })]

  depends_on = [azurerm_kubernetes_cluster.this]
}

resource "helm_release" "runtime_class_manager_crds" {
  name             = "runtime-class-manager-crds"
  namespace        = local.runtime_class_manager_namespace
  create_namespace = true
  chart            = "${local.charts_dir}/runtime-class-manager-crds"
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  timeout          = 300

  depends_on = [helm_release.cert_manager]
}

resource "helm_release" "runtime_class_manager" {
  name             = "runtime-class-manager"
  namespace        = local.runtime_class_manager_namespace
  create_namespace = true
  repository       = "oci://ghcr.io/spinframework/charts"
  chart            = "runtime-class-manager"
  version          = local.runtime_class_manager_chart_version
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  timeout          = 600

  depends_on = [helm_release.runtime_class_manager_crds]
}

resource "helm_release" "spinkube_shim" {
  name            = "spin-shim"
  namespace       = local.runtime_class_manager_namespace
  chart           = "${local.charts_dir}/spinkube-shim"
  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  values = [yamlencode({
    shim = {
      name             = "spin-v2"
      version          = var.spin_shim_version
      runtimeClassName = "wasmtime-spin-v2"
      runtimeHandler   = "spin-v2"
      nodeSelector = {
        "kubernetes.io/os" = "linux"
      }
    }
  })]

  depends_on = [helm_release.runtime_class_manager]
}

resource "helm_release" "spin_operator_crds" {
  name             = "spin-operator-crds"
  namespace        = local.spin_operator_namespace
  create_namespace = true
  chart            = "${local.charts_dir}/spin-operator-crds"
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  timeout          = 300

  depends_on = [helm_release.spinkube_shim]
}

resource "helm_release" "spin_operator" {
  name             = "spin-operator"
  namespace        = local.spin_operator_namespace
  create_namespace = true
  repository       = "oci://ghcr.io/spinframework/charts"
  chart            = "spin-operator"
  version          = local.spin_operator_chart_version
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  timeout          = 600

  depends_on = [helm_release.spin_operator_crds]
}

resource "helm_release" "spin_operator_executor" {
  name            = "spin-operator-executor"
  namespace       = local.spin_operator_namespace
  chart           = "${local.charts_dir}/spin-operator-executor"
  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = 300

  values = [yamlencode({
    executor = {
      name             = "containerd-shim-spin"
      runtimeClassName = "wasmtime-spin-v2"
    }
  })]

  depends_on = [helm_release.spin_operator]
}

resource "helm_release" "keda" {
  name             = "keda"
  namespace        = local.keda_namespace
  create_namespace = true
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.keda_version
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  timeout          = 600

  depends_on = [helm_release.spin_operator_executor]
}

resource "helm_release" "keda_http_addon" {
  name            = local.keda_http_release_name
  namespace       = local.keda_namespace
  repository      = "https://kedacore.github.io/charts"
  chart           = "keda-add-ons-http"
  version         = var.keda_http_addon_version
  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  values = [yamlencode({
    crds = {
      install = true
    }
  })]

  depends_on = [helm_release.keda]
}
