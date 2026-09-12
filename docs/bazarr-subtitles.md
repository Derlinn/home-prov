# Bazarr : sous-titres FR multi-providers avec fallback et synchro auto

Bazarr ne sait garder qu'**un seul fichier par langue** en automatique : chaque nouveau
téléchargement écrase le précédent. Pour avoir plusieurs versions FR (fallback quand
l'une est désynchronisée) sans les chercher à la main, un hook de post-processing
archive les versions remplacées et remplit le pool tout seul.

**Fichiers Git :** `kubernetes/apps/media-server/bazarr/app/`

- `configmap.yaml` : ConfigMap `bazarr-scripts` contenant `save-alt-subtitle.sh`
- `helmrelease.yaml` : monte le script en `persistence.scripts` sur `/scripts/save-alt-subtitle.sh`
- `kustomization.yaml` : référence `configmap.yaml`

Le reste (langues, providers, seuils, synchro) vit dans la DB de Bazarr (`/config`),
donc hors Git : voir « Réglages UI » ci-dessous.

---

## Fonctionnement

Ordre d'exécution interne de Bazarr à chaque téléchargement :

1. Sauvegarde du `.fr.srt`
2. Synchro ffsubsync (si activée et score sous le seuil)
3. Hook post-processing → archivage dans le pool + remplissage auto éventuel

### Pool de fallback

À chaque remplacement du `.fr.srt` par un fichier au contenu différent, l'ancien est
copié en `film.<score>-<provider>.alt.srt` (ex. `film.90.0-opensubtitlescom.alt.srt`).
Jellyfin les liste comme pistes FR supplémentaires, score et provider visibles.

- Déduplication par hash : un contenu déjà présent n'est jamais ré-archivé.
- Plafond `CAP=4` fichiers `.alt` : au-delà, le score le plus faible est évincé.
- Les fichiers `.prevcopy`/`.prevmeta` à côté du `.srt` sont l'état interne du hook
  (copie + score/provider du fichier courant), pas des sous-titres.

### Remplissage automatique

Au premier téléchargement FR d'un film/épisode, le hook interroge l'API locale de
Bazarr (`GET /api/providers/movies|episodes`, clé lue dans
`/config/config/config.yaml`), sélectionne les meilleurs candidats FR normaux
(non HI, non forced, score ≥ `MIN_FETCH_SCORE=60`) de providers distincts, et les
télécharge (`POST`). Chacun repasse par le pipeline ci-dessus : synchro puis
archivage. Les téléchargements sont lancés par score croissant pour que le
meilleur finisse en `.fr.srt` principal.

Garde-fous anti-boucle (les téléchargements API re-déclenchent le hook) :

- Marqueur `film.fr.autofetch.done` : une seule recherche auto toutes les 24 h
  (`MARKER_TTL_SECONDS=86400`) par fichier.
- Lock `/tmp/bazarr-autofetch-<hash>.lock` : pas de remplissage ré-entrant.
- FR uniquement : les autres langues ne font que l'archivage.

Réglables en tête du script : `CAP`, `MIN_FETCH_SCORE`, `MARKER_TTL_SECONDS`.

---

## Réglages UI (Settings > Subtitles, hors Git)

### Custom Post-Processing

Commande (6 arguments) :

```
sh /scripts/save-alt-subtitle.sh "{{subtitles}}" "{{score}}" "{{provider}}" "{{subtitles_language_code2}}" "{{series_id}}" "{{episode_id}}"
```

Seuils séries + films à `100`, ou cases de seuil décochées.

### Audio Synchronization > Advanced FFsubsync Options

- Synchronization Reference : `Use Audio Track as Reference` (des fichiers n'ont
  aucun sous-titre intégré à quoi s'aligner, dont Apocalypse Now BHDStudio)
- Prefer Original Language Audio Track : coché
- Do Not Fix Framerate Mismatch : décoché (corrige la dérive 23.976 ↔ 25 fps)
- Golden-Section Search : coché (optimise décalage + ratio ensemble)
- Max Offset Seconds : `300` (au-delà de 5 min c'est le mauvais montage, pas un
  problème de synchro)
- Generate Debug File : décoché
- Seuils séries + films à `100`

---

## Pièges connus (tous rencontrés en septembre 2026)

- **Tous les seuils Bazarr sont « en dessous de ».** Post-processing comme subsync
  ne tournent que si `score < seuil`. Un seuil à `0` avec l'option activée =
  jamais exécuté, pas toujours. Mettre `100` (ou décocher l'option) pour
  systématiser.
- **Le score n'est pas la synchro.** Un 90/100 mesure la correspondance des
  métadonnées (source, résolution, édition), pas le calage temporel.
- **Les `forced` ne sont jamais synchronisés** (limite native de Bazarr) ; le
  remplissage auto les exclut déjà.
- **Sans synchro, le pool accumule des versions désynchronisées.** Les deux
  features se complètent : le pool garde les alternatives, la synchro les rend
  utilisables.
- **Au-delà de ~5 min de décalage, c'est le mauvais montage** (ex. Redux vs
  Theatrical sur Apocalypse Now) : aucune synchro ne le sauvera, il faut une
  autre version en recherche manuelle.

---

## Vérification

- Dossier du média : jusqu'à 1 `.fr.srt` + 4 `.fr.<score>-<provider>.alt.srt`.
- `History` dans Bazarr : chaque téléchargement (`action` 1/2 en DB,
  `table_history_movie` / `table_history`) doit être suivi d'une entrée
  *« subtitles synchronization ended with an offset of ... »* (`action` 5).
  Exception normale : les `forced`. Pas d'entrée sync = échec (voir
  `System > Logs`, lignes `autofetch:` pour le remplissage auto).
- Jellyfin : les pistes `.alt` sont sélectionnables avec score/provider en titre.
