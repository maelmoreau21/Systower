<div align="center">

# 🏗️ Systower

**Gestionnaire de mises à jour automatique pour conteneurs Docker et système Linux avec Interface Web**

*Une alternative moderne, ultra-légère et améliorée à Watchtower*

[🇬🇧 English](README.md) • [🇫🇷 Français](README.fr.md)

[![Build & Push](https://github.com/maelmoreau21/Systower/actions/workflows/build.yml/badge.svg)](https://github.com/maelmoreau21/Systower/actions/workflows/build.yml)
[![Tests](https://github.com/maelmoreau21/Systower/actions/workflows/test.yml/badge.svg)](https://github.com/maelmoreau21/Systower/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Multi-Arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64%20%7C%20armv7%20%7C%20armv6-purple)](https://github.com/maelmoreau21/Systower)

</div>

---

## ✨ Fonctionnalités

- 🐳 **Mises à jour des conteneurs Docker** — Télécharge les dernières images et recrée automatiquement les conteneurs en préservant 100% de leur configuration (volumes, ports, réseaux, labels, variables d'environnement, redémarrage).
- 🖥️ **Mise à jour du système hôte** — Met à jour directement le système d'exploitation de la machine hôte (Debian, Ubuntu, Raspberry Pi OS, Alpine, Arch, Fedora) sans configuration SSH.
- 🌐 **Interface Web Moderne (FR / EN)** — Dashboard sombre et réactif avec sélecteur de langue (Français / Anglais), logs en temps réel et déclenchement manuel.
- 🔐 **Authentification Simple & OIDC** — Sécurisation par identifiants simples (`USERNAME` & `PASSWORD`) ou SSO OpenID Connect (Authentik, Authelia, Keycloak, etc.).
- 🔔 **Notifications Multi-Canaux** — Alertes immédiates sur **Discord**, **Slack**, **Telegram** et **Webhooks JSON**.
- 🔄 **Rollback Automatique** — En cas de problème au démarrage d'une nouvelle image, Systower restaure instantanément l'ancienne version.
- 🧹 **Nettoyage Automatique** — Suppression des anciennes images inutilisées après une mise à jour réussie.
- 🪶 **Ultra-Léger & Économe** — Moins de 5 Mo de RAM en mode headless, compatible avec tous les Raspberry Pi (`amd64`, `arm64`, `arm/v7`, `arm/v6`).

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
    ports:
      - "8080:8080" # Interface Web (supprime si SYSTOWER_UI_ENABLED: "false")
    volumes:
      # Requis : socket Docker
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config:/config
    environment:
      # Planification (Tous les jours à 4h00 du matin)
      SYSTOWER_CRON: "0 4 * * *"
      SYSTOWER_RUN_ON_START: "true"
      TZ: "Europe/Paris"

      # Mises à jour des conteneurs Docker
      SYSTOWER_DOCKER_ENABLED: "true"
      SYSTOWER_DOCKER_CLEANUP: "true"
      # SYSTOWER_DOCKER_EXCLUDE: "postgres,redis" # Conteneurs à exclure

      # Mise à jour du système hôte (Debian, Ubuntu, Raspberry Pi OS...)
      SYSTOWER_SYSTEM_ENABLED: "false" # Passe à "true" si pid: host est activé
      SYSTOWER_SYSTEM_REBOOT: "false"

      # Interface Web & Authentification
      SYSTOWER_UI_ENABLED: "true" # Passe à "false" pour le mode minimal (< 5MB RAM)
      USERNAME: "admin"
      PASSWORD: "MonMotDePasse"
```

Accède à l'interface sur **`http://localhost:8080`**.

---

## 🔐 Sécurité & Authentification

### 1. Identifiants Simples (Recommandé)
Configure directement dans l'environnement :
```yaml
USERNAME: "admin"
PASSWORD: "MonMotDePasseSecurise"
```

### 2. OIDC Single Sign-On (Authentik, Keycloak, Authelia...)
```yaml
SYSTOWER_OIDC_ENABLED: "true"
SYSTOWER_OIDC_ISSUER: "https://auth.example.com/application/o/systower/"
SYSTOWER_OIDC_CLIENT_ID: "systower-client-id"
SYSTOWER_OIDC_CLIENT_SECRET: "votre-secret"
```

---

## 🔔 Notifications

Active les alertes en définissant les variables correspondantes :

- **Discord** : `SYSTOWER_NOTIFY_DISCORD="https://discord.com/api/webhooks/..."`
- **Slack** : `SYSTOWER_NOTIFY_SLACK="https://hooks.slack.com/services/..."`
- **Telegram** : `SYSTOWER_NOTIFY_TELEGRAM_TOKEN="123456:ABC..."` et `SYSTOWER_NOTIFY_TELEGRAM_CHAT="-100..."`
- **Webhook** : `SYSTOWER_NOTIFY_WEBHOOK="https://automation.example.com/webhook"`

---

## 🏷️ Labels pour Conteneurs

| Label | Exemple | Description |
|:---|:---|:---|
| `systower.exclude` | `"true"` | Exclure ce conteneur des mises à jour |
| `systower.schedule` | `"0 2 * * 0"` | Cron personnalisé pour ce conteneur |
| `systower.stop-timeout` | `"60"` | Délai d'arrêt avant forçage (secondes) |

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
| `SYSTOWER_SYSTEM_ENABLED` | `false` | Activer la mise à jour des paquets de la machine hôte |
| `SYSTOWER_SYSTEM_REBOOT` | `false` | Redémarrage automatique si requis par les paquets |
| `SYSTOWER_UI_ENABLED` | `true` | Activer l'interface Web (port 8080) |
| `USERNAME` | `""` | Nom d'utilisateur pour l'interface Web |
| `PASSWORD` | `""` | Mot de passe pour l'interface Web |

---

## 📄 Licence

Projet distribué sous licence **MIT**.
