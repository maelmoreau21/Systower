# Mises à jour natives Docker Compose (mode manuel)

Cette commande constitue la première brique du support Compose, **pas encore une mise à jour automatique par le daemon**. Elle utilise les fichiers Compose d'origine plutôt qu'une recréation basée sur `docker inspect`.

## Conditions

- Exécuter le binaire Systower sur une machine ayant les commandes `docker` et `docker compose`.
- Le projet Compose, les fichiers `.env` et les éventuels volumes relatifs doivent être accessibles localement.
- Une sauvegarde indépendante des données est indispensable. Docker Compose ne restaure pas les migrations de bases de données.
- Les protections/labels d'exclusion des mises à jour standalone ne sont **pas** appliqués à cette action Compose explicitement demandée. Ne sélectionnez pas des services sensibles sans procédure de maintenance.

## Exemple

Aperçu (sans modification) :

```bash
systower compose update --file /srv/apps/compose.yml --project-directory /srv/apps --service web
```

Exécution explicite :

```bash
systower compose update --file /srv/apps/compose.yml --project-directory /srv/apps --service web --apply
```

Plusieurs services peuvent être sélectionnés en répétant `--service`. Plusieurs fichiers `-f` permettent les configurations superposées.

Le programme exécute successivement `docker compose config --quiet`, `docker compose pull --ignore-buildable web`, puis `docker compose up --detach --no-deps --pull never web`. Le paramètre `--no-deps` évite de démarrer ou mettre à jour les dépendances non sélectionnées. En revanche, `up` peut démarrer un **service sélectionné** s'il était arrêté.

## Limites

- Pas de tâche planifiée Compose, pas de découverte automatique des projets, pas de suivi de digest distant.
- Pas de rollback transactionnel Compose ni de garantie de continuité de service.
- Le conteneur Docker Systower actuel n'embarque pas forcément le binaire `docker compose` : cette commande vise d'abord l'exécution sur l'hôte ou dans un conteneur muni du CLI et des fichiers Compose.


## Mises à jour automatiques (activation explicite)

Systower peut exécuter une liste de services Compose au rythme de `SYSTOWER_CRON`. **Cette fonction est désactivée par défaut** et ne détecte pas automatiquement les projets.

```yaml
services:
  systower:
    build:
      context: .
      args:
        WITH_COMPOSE: "true"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /srv/projects:/srv/projects:ro
      - systower-state:/var/lib/systower
    environment:
      SYSTOWER_DOCKER_ENABLED: "false"
      SYSTOWER_COMPOSE_ENABLED: "true"
      SYSTOWER_COMPOSE_TARGETS_JSON: >-
        [{"files":["/srv/projects/web/compose.yml"],
          "project_directory":"/srv/projects/web",
          "services":["web"]}]
      SYSTOWER_CRON: "0 4 * * *"
      SYSTOWER_DRY_RUN: "true"
volumes:
  systower-state:
```

Pour activer les actions réelles, remplacez `SYSTOWER_DRY_RUN` par `false` après vérification de la configuration. Le CLI Docker Compose n'est embarqué que dans une image construite avec `WITH_COMPOSE=true` ; la taille de cette variante est plus importante. Les chemins des projets montés doivent également correspondre aux chemins visibles sur l'hôte pour les bind mounts. Le socket Docker accorde des privilèges très élevés.

Avant chaque mise à jour, Systower vérifie la configuration et exige que **tous les services explicitement sélectionnés soient déjà démarrés**. Les services arrêtés ne sont donc pas relancés accidentellement. Puis il exécute les commandes pull et up, sans prétendre qu'une nouvelle image était forcément disponible.

**Limites :** pas de rollback transactionnel Compose, pas de sauvegarde automatique des données, pas de vérification distante des digests ni de garantie de disponibilité applicative. Les fichiers `.env` et les projets doivent être lisibles depuis le conteneur. Évitez les bases de données, VPN et DNS sans procédure de maintenance dédiée.
