locals {
  apps = {
    twingate = {
      service_account_name      = "twingate-sa"
      service_account_namespace = "default"
    }
  }
}

resource "vault_policy" "app_policy" {
  for_each = local.apps
  name     = each.key
  policy   = templatefile("${path.module}/policies/secrets.hcl.tftpl", { app = each.key })
}

resource "vault_kubernetes_auth_backend_role" "app_role" {
  for_each                         = local.apps
  backend                          = "kubernetes"
  role_name                        = each.key
  bound_service_account_names      = [each.value.service_account_name]
  bound_service_account_namespaces = [each.value.service_account_namespace]
  token_policies                   = [vault_policy.app_policy[each.key].name]
  token_ttl                        = 3600
}