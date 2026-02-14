# Bootstrap Flux avec Flux Operator

Ce guide explique comment bootstraper Flux sur un nouveau cluster en utilisant Flux Operator et FluxInstance.

## Pre-requis

- `kubectl` configure avec acces au cluster
- `helm` installe
- Un GitHub Fine-Grained PAT avec les permissions :
  - **Contents** : `Read-only`
  - **Metadata** : `Read-only`
  - Scope : uniquement le repo `Derlinn/home-prov`
- La cle age pour SOPS

## Etapes

### 1. Installer Flux Operator

```bash
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  -n flux-system --create-namespace
```

Verifier que l'operator est running :

```bash
kubectl get pods -n flux-system
```

### 2. Creer la FluxInstance

Les CRDs Flux standard (`HelmRelease`, `GitRepository`, `Kustomization`, etc.) n'existent pas encore.
Elles sont installees par la FluxInstance, il faut donc la creer manuellement :

```bash
kubectl apply -f - <<'EOF'
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux
  namespace: flux-system
spec:
  distribution:
    version: "2.x"
    registry: "ghcr.io/fluxcd"
    artifact: "oci://ghcr.io/controlplaneio-fluxcd/flux-operator-manifests:v0.36.0"
  components:
    - source-controller
    - kustomize-controller
    - helm-controller
    - notification-controller
  cluster:
    networkPolicy: false
    multitenant: false
    type: kubernetes
EOF
```

Attendre que tous les controllers soient running :

```bash
kubectl get pods -n flux-system
# source-controller, kustomize-controller, helm-controller, notification-controller doivent etre Running
```

### 3. Creer les secrets

**Secret Git** (pour acceder au repo prive) :

```bash
kubectl create secret generic flux-system \
  -n flux-system \
  --from-literal=username=git \
  --from-literal=password=<GITHUB_PAT>
```

**Secret SOPS** (pour le dechiffrement des secrets) :

```bash
kubectl create secret generic sops-age \
  -n flux-system \
  --from-file=age.agekey=<CHEMIN_VERS_CLE_AGE>
```

### 4. Appliquer la configuration Flux

```bash
kubectl apply -k kubernetes/apps/flux-system/
```

### 5. Verifier la reconciliation

```bash
kubectl get kustomizations -n flux-system
```

Les Kustomizations doivent passer a `Ready: True` :

- `flux-operator` : installe Flux Operator via HelmRelease (se reconcilie avec la version du repo)
- `flux-instance` : cree la FluxInstance complete avec tous les patches (depend de flux-operator)
- `cluster-apps` : reconcilie tout `./kubernetes/apps` avec SOPS et patches globaux

## Fonctionnement

Une fois bootstrap, Flux se gere entierement depuis le repo Git :

```
flux-operator (HelmRelease)
  └── flux-instance (HelmRelease, depend de flux-operator)
        └── deploie les controllers Flux avec patches (SOPS, concurrency, caching, etc.)
              └── cluster-apps (Kustomization)
                    └── reconcilie toutes les apps dans kubernetes/apps/
```

La FluxInstance creee manuellement a l'etape 2 sera remplacee par celle definie dans le repo
lors de la reconciliation de `flux-instance`.
