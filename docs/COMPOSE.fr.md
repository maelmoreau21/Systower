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
