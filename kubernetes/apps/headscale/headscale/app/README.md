# headscale / headplane

Headscale + Headplane dans le même Pod (`shareProcessNamespace: true`), auth OIDC via Authentik.

## Secrets

### `secret.sops.yaml` — chiffré SOPS/AGE
- `headscale-oidc.client-secret`
- `headplane-oidc.client-secret`

```bash
sops kubernetes/apps/headscale/headscale/app/secret.sops.yaml
```

### `headplane-secrets` — créé par Vaultwarden Kubernetes Secrets Sync (non dans le repo)
- `api-key` — clé API Headscale
- `cookie-secret` — secret de session Headplane

## Authentik

Deux providers OAuth2 distincts :
- **headscale** : redirect `https://headscale-01.linderis.fr/oidc/callback`, scope `groups` requis, groupe `headscale_users`
- **headplane** : redirect `https://headplane.linderis.fr/admin/callback`, `client_id` en clair dans `headplane-config.yaml`

Le scope `groups` nécessite un Property Mapping custom :
```python
return list(request.user.ak_groups.values_list("name", flat=True))
```
