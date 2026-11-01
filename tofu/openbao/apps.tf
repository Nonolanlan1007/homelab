locals {
  apps = {
    twingate = {
      service_account_name      = "twingate-sa"
      service_account_namespace = "default"
    }
    affine = {
      service_account_name      = "affine-sa"
      service_account_namespace = "default"
    }
    authentik = {
      service_account_name      = "authentik-sa"
      service_account_namespace = "default"
    }
    convertx = {
      service_account_name      = "convertx-sa"
      service_account_namespace = "default"
    }
    gitea = {
      service_account_name      = "gitea-sa"
      service_account_namespace = "default"
    }
    immich = {
      service_account_name      = "immich-sa"
      service_account_namespace = "default"
    }
    linkwarden = {
      service_account_name      = "linkwarden-sa"
      service_account_namespace = "default"
    }
    matomo = {
      service_account_name      = "matomo-sa"
      service_account_namespace = "default"
    }
    matrix = {
      service_account_name      = "matrix-sa"
      service_account_namespace = "default"
    }
    paperless = {
      service_account_name      = "paperless-sa"
      service_account_namespace = "default"
    }
    qbittorrent = {
      service_account_name      = "qbittorrent-sa"
      service_account_namespace = "default"
    }
    seafile = {
      service_account_name      = "seafile-sa"
      service_account_namespace = "default"
    }
    sharry = {
      service_account_name      = "sharry-sa"
      service_account_namespace = "default"
    }
    traefik = {
      service_account_name      = "traefik-sa"
      service_account_namespace = "kube-system"
    }
    vaultwarden = {
      service_account_name      = "vaultwarden-sa"
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