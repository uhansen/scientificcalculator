resource "kubernetes_secret_v1" "ghcr_pull_secret" {
  metadata {
    name      = local.ghcr_pull_secret_name
    namespace = local.app_namespace
  }

  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.ghcr_username
          password = var.ghcr_token
          auth     = base64encode("${var.ghcr_username}:${var.ghcr_token}")
        }
      }
    })
  }

  depends_on = [helm_release.spin_operator_executor]
}

resource "helm_release" "thecalculator_application" {
  name            = var.app_name
  namespace       = local.app_namespace
  chart           = "${local.charts_dir}/thecalculator-app"
  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = 300

  values = [yamlencode({
    app = {
      name            = var.app_name
      namespace       = local.app_namespace
      host            = var.app_host
      image           = var.image
      imagePullSecret = local.ghcr_pull_secret_name
      executor        = "containerd-shim-spin"
    }
    autoscaling = {
      minReplicas     = 1
      maxReplicas     = 5
      concurrency     = 10
      scaledownPeriod = 60
    }
  })]

  depends_on = [
    kubernetes_secret_v1.ghcr_pull_secret,
    helm_release.keda_http_addon,
  ]
}
