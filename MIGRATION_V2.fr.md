# Migration V1 vers V2

Ce document décrit la migration historique de l’ancienne implémentation Bash vers Systower 2.0.0.

## Procédure

1. Valider l’image 2.0.0 avec `systower check` et `systower docker check` avant le déploiement.
2. Sauvegarder le volume de logs/configuration V1.
3. Utiliser un volume d’état dédié pour V2. V2 ne supprime pas les données V1.
4. Commencer avec `SYSTOWER_DRY_RUN=true` ou `SYSTOWER_DOCKER_MONITOR_ONLY=true`.

## Changements importants

- V2 utilise directement l’API Docker et ne nécessite plus Docker CLI, jq, Bash, cron ou curl.
- Les conteneurs réseau et ceux qui montent le socket Docker sont protégés par défaut.
- Les mises à jour sont comparées par identité d’image.
- Un conteneur sans healthcheck est refusé par défaut. `SYSTOWER_DOCKER_ALLOW_NO_HEALTHCHECK=true` doit être explicite.
- Un conteneur Compose n’est pas recréé si le fichier source du projet est inaccessible.
- Les mises à jour Linux restent facultatives et désactivées par défaut.

## État et rollback

Monter `/var/lib/systower` comme volume persistant. Le journal JSONL et le verrou empêchent les opérations concurrentes. Un rollback n’est annoncé réussi qu’après redémarrage et vérification de l’ancien conteneur.