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

## allow-egress-https

**Fichier :** `policies/allow-egress-https.yaml`

Tous les pods peuvent faire des requetes sortantes sur le port 443. Couvre les appels vers des registres OCI, APIs externes, etc.

---

## allow-ingress-lan

**Fichier :** `policies/allow-ingress-lan.yaml`

Tous les pods acceptent du trafic entrant depuis le reseau local.

- `10.25.0.0/16` — tout le reseau home (temporaire, a restreindre)
- `10.25.200.0/24` — VLAN mgmt (permanent)

---

## allow-flux-internal

**Fichier :** `policies/allow-flux-internal.yaml`

Les pods du namespace `flux-system` peuvent communiquer entre eux (ingress et egress). Couvre la communication interne entre les controllers Flux.

---

## allow-prometheus-scrape

**Fichier :** `policies/allow-prometheus-scrape.yaml`

Prometheus (`observability`, label `app.kubernetes.io/name: prometheus`) peut scraper tous les pods sur les ports de metriques : 9090, 9100, 9153, 9402, 8080, 8081.

---

## allow-prometheus-egress

**Fichier :** `policies/allow-prometheus-egress.yaml`

Prometheus peut initier des connexions vers tous les endpoints du cluster sur les memes ports de metriques : 9090, 9100, 9153, 9402, 8080, 8081.

---

## allow-hubble / allow-hubble-ui

**Fichier :** `policies/allow-hubble.yaml`

- `allow-hubble` : Hubble Relay (`kube-system`, label `app.kubernetes.io/name: hubble-relay`) accepte les connexions de tous les pods sur 4245
- `allow-hubble-ui` : Hubble UI peut se connecter a Hubble Relay sur 4245

---

## allow-longhorn-internal

**Fichier :** `policies/allow-longhorn.yaml`

Tous les pods du namespace `longhorn-system` peuvent communiquer entre eux (ingress et egress). Couvre la replication des volumes et la communication entre les composants Longhorn.

---

## allow-envoy-gateway

**Fichier :** `policies/allow-envoy-gateway.yaml`

Trafic entrant vers les pods Envoy proxy (gateway externe et interne).

- `allow-envoy-gateway` (envoy-external) : accepte tout trafic entrant depuis `0.0.0.0/0` sur 80, 443, 10080, 10443. Les ports 10080/10443 sont les ports reels du container (le service mappe 80->10080 et 443->10443 car un container ne peut pas binder < 1024 sans privileges). Necessaire egalement pour le hairpin NAT (pods internes qui passent par l'URL externe). Accepte aussi le port 19003 depuis le subnet des noeuds (`10.25.30.0/24`) pour les readiness probes Kubelet.
- `allow-envoy-gateway-xds` (control plane) : les pods du namespace `network` peuvent atteindre le control plane Envoy Gateway sur 18000 (protocole xDS/gRPC pour la distribution de configuration).
- `allow-envoy-gateway-internal` (envoy-internal) : accepte le trafic entrant depuis `10.25.0.0/16` sur 80, 443, 10080, 10443.

---

## allow-envoy-egress

**Fichier :** `policies/allow-envoy-egress.yaml`

Tous les pods du namespace `network` (Envoy proxies) peuvent se connecter vers n'importe quel endpoint du cluster sur : 80, 443, 8080, 8443, 18000.

---

## allow-envoy-backends

**Fichier :** `policies/allow-envoy-backends.yaml`

Tous les pods du cluster acceptent du trafic entrant depuis les pods Envoy external (`network`, label `gateway.envoyproxy.io/owning-gateway-name: envoy-external`) sur : 80, 443, 8000, 8080, 8443. Le port 8000 couvre l'UI Longhorn.
