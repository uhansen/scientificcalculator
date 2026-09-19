resource "helm_release" "envoy_gateway" {
  name             = local.envoy_gateway_release_name
  namespace        = local.envoy_gateway_namespace
  create_namespace = true
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = var.envoy_gateway_version
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  timeout          = 600

  values = [yamlencode({
    crds = {
      enabled = true
    }
  })]

  depends_on = [
    helm_release.cert_manager,
    helm_release.keda_http_addon,
  ]
}

resource "helm_release" "envoy_gateway_resources" {
  name            = "envoy-gateway-resources"
  namespace       = local.app_namespace
  chart           = "${local.charts_dir}/envoy-gateway-resources"
  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = 300

  values = [yamlencode({
    app = {
      name      = var.app_name
      host      = var.app_host
      namespace = local.app_namespace
    }
    envoyGateway = {
      className   = local.envoy_gateway_class_name
      gatewayName = local.envoy_gateway_name
      proxy = {
        name        = local.envoy_proxy_name
        namespace   = local.app_namespace
        annotations = local.envoy_nlb_annotations
      }
    }
    keda = {
      namespace              = local.keda_namespace
      interceptorServiceName = local.keda_http_interceptor_proxy_service
      interceptorServicePort = 8080
    }
  })]

  depends_on = [
    helm_release.envoy_gateway,
    helm_release.keda_http_addon,
    helm_release.thecalculator_application,
  ]
}
