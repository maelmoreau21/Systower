<div align="center">

# 🏗️ Systower

**Gestionnaire de mises à jour automatique ultra-léger pour conteneurs Docker et système hôte Linux**

*Une alternative moderne, ultra-légère (~25 Mo, < 2 Mo RAM) et améliorée à Watchtower*

[🇬🇧 English](README.md) • [🇫🇷 Français](README.fr.md)

[![Build & Push](https://github.com/maelmoreau21/Systower/actions/workflows/build.yml/badge.svg)](https://github.com/maelmoreau21/Systower/actions/workflows/build.yml)
[![Tests](https://github.com/maelmoreau21/Systower/actions/workflows/test.yml/badge.svg)](https://github.com/maelmoreau21/Systower/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Image Size](https://img.shields.io/badge/taille%20image-~25%20Mo-brightgreen)](https://github.com/maelmoreau21/Systower)
[![RAM](https://img.shields.io/badge/RAM-%3C%202%20Mo-brightgreen)](https://github.com/maelmoreau21/Systower)
[![Multi-Arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64%20%7C%20armv7%20%7C%20armv6-purple)](https://github.com/maelmoreau21/Systower)

</div>

---

## ✨ Fonctionnalités

- 🐳 **Mises à jour automatiques des conteneurs Docker** — Télécharge les dernières images et recrée automatiquement les conteneurs en préservant 100% de leur configuration (volumes, ports, réseaux, labels, variables d'environnement, restart policies).
- 🖥️ **Mise à jour du système hôte** — Met à jour directement le système d'exploitation de la machine locale (Debian, Ubuntu, Raspberry Pi OS, Alpine, Arch, Fedora) sans aucune configuration SSH.
- 🚫 **Exclusion facile de conteneurs** — Excluez les conteneurs que vous ne souhaitez pas mettre à jour via variable d'environnement ou via label Docker.
- 🔔 **Notifications Multi-Canaux** — Alertes immédiates sur **Discord**, **Slack**, **Telegram** et **Webhooks JSON**.
- 🔄 **Rollback Automatique** — En cas de problème au démarrage d'une nouvelle image, Systower restaure instantanément l'ancienne version.
- 🧹 **Nettoyage Automatique** — Suppression des anciennes images inutilisées après une mise à jour réussie.
- 🪶 **Ultra-Léger & Économe** — Image de **~25 Mo**, consommation de **< 2 Mo de RAM**, compatible avec toutes les architectures (`amd64`, `arm64`, `arm/v7`, `arm/v6`).

---

## 🚀 Démarrage Rapide

### `docker-compose.yml`

```yaml
services:
  systower:
    image: ghcr.io/maelmoreau21/systower:latest
    container_name: systower
    restart: unless-stopped
    # Optionnel : active pid: "host" et privileged: true si tu souhaites aussi mettre à jour les paquets de l'OS hôte
    # pid: "host"
    # privileged: true
    volumes:
      # Requis : socket Docker
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      # Planification (Tous les jours à 4h00 du matin)
      SYSTOWER_CRON: "0 4 * * *"
      SYSTOWER_RUN_ON_START: "true"
      TZ: "Europe/Paris"

      # Mises à jour des conteneurs Docker
      SYSTOWER_DOCKER_ENABLED: "true"
      SYSTOWER_DOCKER_CLEANUP: "true"

      # Exclusion de conteneurs (Optionnel)
      # SYSTOWER_DOCKER_EXCLUDE: "postgres,redis,mon-conteneur"

      # Mise à jour du système hôte (Debian, Ubuntu, Raspberry Pi OS...)
      SYSTOWER_SYSTEM_ENABLED: "false" # Passe à "true" si pid: host est activé
      SYSTOWER_SYSTEM_REBOOT: "false"
```

Lancez Systower :
```bash
docker compose up -d
```

---

## 🚫 Comment empêcher la mise à jour de certains conteneurs ?

Vous avez **3 méthodes simples** selon vos préférences :

### Méthode 1 : Liste d'exclusion globale (Recommandé)
Dans votre `docker-compose.yml`, ajoutez les noms des conteneurs séparés par une virgule :
```yaml
environment:
  SYSTOWER_DOCKER_EXCLUDE: "postgres,redis,mon_application,database"
```

### Méthode 2 : Via un Label Docker sur le conteneur lui-même
Ajoutez le label `systower.exclude: "true"` directement sur le service que vous ne voulez pas mettre à jour :
```yaml
services:
  ma_base_de_donnees:
    image: postgres:16
    labels:
      systower.exclude: "true"
```
Systower inspecte automatiquement les labels et ignorera toujours ce conteneur.

### Méthode 3 : Mode Liste Blanche (Include Only)
Si vous souhaitez que Systower ne mette à jour **que** certains conteneurs spécifiques et ignore tous les autres :
```yaml
environment:
  SYSTOWER_DOCKER_INCLUDE_ONLY: "sonarr,radarr,nginx"
```

---

## 🔔 Notifications

Activez les alertes en définissant les variables correspondantes :

- **Discord** : `SYSTOWER_NOTIFY_DISCORD="https://discord.com/api/webhooks/..."`
- **Slack** : `SYSTOWER_NOTIFY_SLACK="https://hooks.slack.com/services/..."`
- **Telegram** : `SYSTOWER_NOTIFY_TELEGRAM_TOKEN="123456:ABC..."` et `SYSTOWER_NOTIFY_TELEGRAM_CHAT="-100..."`
- **Webhook** : `SYSTOWER_NOTIFY_WEBHOOK="https://automation.example.com/webhook"`

---

## ⚙️ Référence des Variables d'Environnement

| Variable | Défaut | Description |
|:---|:---|:---|
| `SYSTOWER_CRON` | `0 4 * * *` | Expression cron pour les vérifications |
| `SYSTOWER_RUN_ON_START` | `true` | Exécuter une vérification dès le démarrage |
| `SYSTOWER_LOG_LEVEL` | `info` | Niveau de log (`debug`, `info`, `warn`, `error`) |
| `SYSTOWER_DRY_RUN` | `false` | Mode simulation (aucune modification appliquée) |
| `TZ` | `UTC` | Fuseau horaire (ex: `Europe/Paris`) |
| `SYSTOWER_DOCKER_ENABLED` | `true` | Activer les mises à jour des conteneurs |
| `SYSTOWER_DOCKER_CLEANUP` | `true` | Supprimer les anciennes images après mise à jour |
| `SYSTOWER_DOCKER_EXCLUDE` | `""` | Liste des conteneurs à exclure séparés par des virgules |
| `SYSTOWER_DOCKER_INCLUDE_ONLY` | `""` | Si défini, seuls ces conteneurs seront mis à jour |
| `SYSTOWER_DOCKER_STOP_TIMEOUT` | `30` | Délai d'arrêt avant forçage (secondes) |
| `SYSTOWER_SYSTEM_ENABLED` | `false` | Activer la mise à jour des paquets de la machine hôte |
| `SYSTOWER_SYSTEM_REBOOT` | `false` | Redémarrage automatique si requis par les paquets |
| `SYSTOWER_NOTIFY_ENABLED` | `false` | Activer le système de notifications |

---

## 📄 Licence

Projet distribué sous licence **MIT**.
