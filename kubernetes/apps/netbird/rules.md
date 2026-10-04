# NetBird mesh rules

Live state of the self-hosted NetBird mesh (`netbird.linderis.fr`). Most of
this is API-managed, not Git-managed: the operator CRDs cannot express
host/subnet policy destinations (and standalone group-to-group `NBPolicy`
objects silently create nothing upstream), so policies, routes, DNS and the
IdP are configured through the management API. This file is the source of
truth — update it on every mesh change.

## Access model

Default policy is **disabled**. Only the rules below apply (zero trust —
anything not listed is denied):

| Policy | Sources | Destination | Ports |
|---|---|---|---|
| `dns-access` | `linderis_netbird_users`, `linderis_netbird_admins` | host `10.25.30.4` | UDP+TCP 53 |
| `lambda-lan-443` | `linderis_netbird_users` | subnet `10.25.50.0/24` | TCP 443 |
| `admins-lan-all` | `linderis_netbird_admins` | subnet `10.25.0.0/16` | all |

## Routes (`linderis` network, 2 `lan` routing peers)

| Resource | Address | Distributed to |
|---|---|---|
| `lan-services` | `10.25.50.0/24` | users, admins |
| `lan-dns-host` | `10.25.30.4/32` | users, admins |
| `lan-full` | `10.25.0.0/16` | admins only |

## DNS

Nameserver group `lan-dns`: `10.25.30.4` (UDP 53) for `linderis.fr` only
(split-horizon, non-primary). Pushed by management, not enforced on rooted
clients.

## Identity

Embedded IdP (owner account, bcrypt hash in `netbird-config` secret) plus
external OIDC connector `Authentik` (issuer
`https://authentik.linderis.fr/application/o/netbird/`, client `netbird`).
JWT group sync is on (`groups` claim, allowlist: `linderis_netbird`,
`linderis_netbird_users`, `linderis_netbird_admins`). User auto-approval is
on; peer approval is off. Regular `user` role cannot deregister peers —
admin only.

Authentik side (Git-managed blueprint `authentik/app/blueprints/netbird.yaml`):
groups `linderis_netbird`, `linderis_netbird_users`, `linderis_netbird_admins`,
all bound to the NetBird app, `groups` scope exposed.

## Ingress (Git-managed)

Split `HTTPRoute`: peers/API/signal/relay on `envoy-external`, dashboard plus
`/api`+`/oauth2` on `envoy-internal` (same hostname, split-horizon DNS).
Public traffic arrives via the VPS rathole tunnel (client in `network`
namespace → `envoy-external:443`), not Cloudflare (its Bot Fight Mode 403s
gRPC clients).
