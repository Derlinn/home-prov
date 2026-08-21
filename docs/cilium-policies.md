# Cilium Network Policies

Toutes les policies sont des `CiliumClusterwideNetworkPolicy` (scope cluster entier).

Le modele est : une seule policy cree le default-deny, toutes les autres utilisent `enableDefaultDeny: false` et ajoutent uniquement des regles d'autorisation.

---

## default-deny

**Fichier :** `policies/default-deny.yaml`

Policy centrale qui active le deny implicite sur tous les pods (`endpointSelector: {}`).

- Ingress autorise : trafic depuis le noeud hote (`host`)
- Egress autorise : trafic vers le noeud hote (`host`) et vers `kube-apiserver`

Tout ce qui n'est pas couvert par une autre policy allow-* est refuse.

---

## allow-kube-api

**Fichier :** `policies/allow-kube-api.yaml`

Tous les pods peuvent atteindre l'API Kubernetes.

- Egress vers `kube-apiserver` sur 6443
- Egress vers `10.25.30.48/29` sur 7445 (KubePrism — load-balancing local vers l'API)

---

## allow-dns / allow-dns-ingress

**Fichier :** `policies/allow-dns.yaml`

- `allow-dns` : tous les pods peuvent envoyer des requetes DNS vers CoreDNS (`kube-system`, label `k8s-app: kube-dns`) sur les ports 53 UDP/TCP
- `allow-dns-ingress` : CoreDNS accepte les requetes DNS de tous les pods

---

## allow-coredns-upstream

**Fichier :** `policies/allow-coredns-upstream.yaml`

CoreDNS peut faire des requetes DNS vers n'importe quelle destination externe (`0.0.0.0/0`) sur 53 UDP/TCP. Necessaire pour la resolution des noms externes.

---

## allow-https-egress

**Fichier :** `policies/allow-https-egress.yaml`

Tous les pods peuvent faire des requetes sortantes sur le port 443. Couvre les appels vers des registres OCI, APIs externes, etc.

---

## allow-lan-ingress

**Fichier :** `policies/allow-lan-ingress.yaml`

Tous les pods acceptent du trafic entrant depuis le reseau local.

- `10.25.0.0/16` — tout le reseau home (temporaire, a restreindre)
- `10.25.200.0/24` — VLAN mgmt (permanent)

---

## allow-flux-internal

**Fichier :** `policies/allow-flux-internal.yaml`

Les pods du namespace `flux-system` peuvent communiquer entre eux (ingress et egress). Couvre la communication interne entre les controllers Flux.

---

## allow-prometheus-ingress

**Fichier :** `policies/allow-prometheus-ingress.yaml`

Prometheus (`observability`, label `app.kubernetes.io/name: prometheus`) peut scraper tous les pods sur 18 ports de metriques : 9090, 9100, 9153, 9402, 8080 (dont gatus), 8081, 9500 (longhorn-manager), 9962 (cilium-agent), 9963 (cilium-operator), 9964 (envoy-metrics), 9965 (hubble), 19001 (envoy-gateway), 7979 (external-dns), 9300 (authentik), 8443 (kube-green), 10250 (metrics-server), 80 (echo), 9115 (blackbox-exporter).

Cette policy doit rester symetrique avec `allow-prometheus-egress` : un port present d'un seul cote laisse le scrape en timeout.

---

## allow-prometheus-egress

**Fichier :** `policies/allow-prometheus-egress.yaml`

Prometheus peut initier des connexions vers tous les endpoints du cluster sur 17 ports : les memes que `allow-prometheus-ingress`, sauf 3001 et 9115 qui sont couverts par `allow-observability-internal` (meme namespace).

---

## allow-hubble / allow-hubble-ui

**Fichier :** `policies/allow-hubble.yaml`

- `allow-hubble` : Hubble Relay (`kube-system`, label `app.kubernetes.io/name: hubble-relay`) accepte les connexions de tous les pods sur 4245
- `allow-hubble-ui` : Hubble UI peut se connecter a Hubble Relay sur 4245

---

## allow-longhorn-internal

**Fichier :** `policies/allow-longhorn-internal.yaml`

Tous les pods du namespace `longhorn-system` peuvent communiquer entre eux (ingress et egress). Couvre la replication des volumes et la communication entre les composants Longhorn.

---

## allow-envoy-gateway

**Fichier :** `policies/allow-envoy-gateway.yaml`

Trafic entrant vers les pods Envoy proxy (gateway externe et interne).

- `allow-envoy-gateway` (envoy-external) : ce Gateway n'a pas d'IP LoadBalancer, il n'est servi que par le tunnel Cloudflare. Seul le pod `cloudflare-tunnel` du namespace `network` est autorise en entree, sur 443 et 10443. Les ports 10080/10443 sont les ports reels du container (le service mappe 80->10080 et 443->10443 car un container ne peut pas binder < 1024 sans privileges). Accepte aussi le port 19003 depuis le subnet des noeuds (`10.25.30.0/24`) pour les readiness probes Kubelet.
- `allow-envoy-gateway-xds` (control plane) : les pods du namespace `network` peuvent atteindre le control plane Envoy Gateway sur 18000 (protocole xDS/gRPC pour la distribution de configuration).
- `allow-envoy-gateway-internal` (envoy-internal) : accepte le trafic entrant depuis `10.25.0.0/16` sur 80, 443, 10080, 10443.

---

## allow-envoy-egress

**Fichier :** `policies/allow-envoy-egress.yaml`

Tous les pods du namespace `network` (Envoy proxies) peuvent se connecter vers n'importe quel endpoint du cluster sur : 80, 443, 8000, 8080, 8443, 18000. Le port 8000 couvre l'UI Longhorn.

---

## allow-envoy-backends

**Fichier :** `policies/allow-envoy-backends.yaml`

Tous les pods du cluster acceptent du trafic entrant depuis les pods Envoy external (`network`, label `gateway.envoyproxy.io/owning-gateway-name: envoy-external`) sur : 80, 443, 8000, 8080, 8443. Le port 8000 couvre l'UI Longhorn.

---

## allow-envoy-clusterip

**Fichier :** `policies/allow-envoy-clusterip.yaml`

Tous les pods peuvent faire de l'egress vers les ports 10080 et 10443. Necessaire car le socket-LB de Cilium reecrit les connexions vers les ClusterIP Envoy (80→10080, 443→10443) avant l'evaluation des politiques d'egress — sans cette regle, la connexion serait bloquee au niveau du pod source.

---

## Policies "internal" (communication intra-namespace)

Meme forme pour toutes : les pods selectionnes acceptent l'ingress et l'egress depuis/vers les pods du meme perimetre, sans restriction de port.

| Policy | Fichier | Perimetre |
|---|---|---|
| `allow-observability-internal` | `policies/allow-observability-internal.yaml` | namespace `observability` |
| `allow-authentik-internal` | `policies/allow-authentik-internal.yaml` | namespace `authentik` |
| `allow-devtools-internal` | `policies/allow-devtools-internal.yaml` | namespace `devtools` |
| `allow-media-server-internal` | `policies/allow-media-server-internal.yaml` | namespace `media-server` |
| `allow-vaultwarden-internal` | `policies/allow-vaultwarden-internal.yaml` | namespace `vaultwarden` |
| `allow-netbox-internal` | `policies/allow-netbox-internal.yaml` | namespace `default`, label `app.kubernetes.io/instance: netbox` |
| `allow-rackula-internal` | `policies/allow-rackula-internal.yaml` | namespace `default`, label `app.kubernetes.io/instance: rackula` (frontend nginx vers son API sur 3001) |

C'est `allow-observability-internal` qui autorise Prometheus a scraper Gatus (8080) et blackbox-exporter (9115) sans que ces ports figurent dans `allow-prometheus-egress`.

---

## Egress vers des cibles externes

| Policy | Fichier | Source | Destination | Ports |
|---|---|---|---|---|
| `allow-asustor-egress` | `policies/allow-asustor-egress.yaml` | Prometheus | `10.25.30.1/32` (NAS) | 9100, 9633 |
| `allow-blackbox-egress` | `policies/allow-blackbox-egress.yaml` | blackbox-exporter | `10.25.30.1/32` (NAS) | 8001 |
| `allow-mktxp-egress` | `policies/allow-mktxp-egress.yaml` | mktxp | `10.25.200.0/24` (VLAN mgmt) | 8728 (API Mikrotik) |
| `allow-gatus-egress` | `policies/allow-gatus-egress.yaml` | gatus | `10.25.30.0/24` | ICMP echo (type 8) |
| `allow-wireguard-egress` | `policies/allow-wireguard-egress.yaml` | vpn-stack (`media-server`) | `world` | 51820 UDP |

> `allow-uptime-kuma-egress` est **obsolete depuis le 2026-08-11** (uptime-kuma remplace par Gatus).
> Le fichier reste dans le repo mais n'est plus reference dans `policies/kustomization.yaml`.

---

## allow-rathole-egress / allow-headscale-from-rathole

**Fichier :** `policies/allow-rathole-egress.yaml`

- `allow-rathole-egress` : le client rathole (`network`, label `app: rathole-client`) sort vers le VPS `212.227.22.223/32` sur 2333, et vers les pods du namespace `headscale` sur 47239
- `allow-headscale-from-rathole` : headscale accepte l'ingress du client rathole sur 47239

---

## Namespaces sans policy dediee

`cert-manager`, `kube-green`, `kubernetes-replicator` et `system-upgrade` n'ont aucune policy propre. Ils fonctionnent uniquement grace aux policies a `endpointSelector: {}` qui s'appliquent a tous les pods : `default-deny` (vers l'hote et l'API), `allow-kube-api`, `allow-dns`, `allow-https-egress` et `allow-lan-ingress`.

Consequence pratique : ces composants peuvent joindre l'API Kubernetes, le DNS et l'exterieur en HTTPS, mais rien d'autre. Un besoin sortant sur un port different demande une policy dediee.

