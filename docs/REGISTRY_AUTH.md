# Private OCI/Docker registries

Systower supports optional registry credentials for Engine API image pulls using an explicitly mounted **Docker `config.json` file**.

1. Create a dedicated, least-privilege read-only registry token.
2. Create a Docker `config.json` with inline `auths` (the `auth` entry is base64-encoded `username:token`, **not encryption**):

```json
{
  "auths": {
    "ghcr.io": {
      "auth": "BASE64_USERNAME_COLON_TOKEN"
    }
  }
}
```

3. Store the file outside your repository, restrict permissions, and mount it as a read-only secret:

```yaml
services:
  systower:
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /srv/systower/secrets/docker-config.json:/run/secrets/docker-config.json:ro
    environment:
      SYSTOWER_DOCKER_AUTH_CONFIG: /run/secrets/docker-config.json
```

Systower selects credentials by the registry hostname in the image reference. It supports GHCR and other named registries as well as Docker Hub's standard `https://index.docker.io/v1/` auth key. Other images pull anonymously.

**Limitations:** This is not a general registry-management implementation. Docker Desktop credential helpers (`credsStore` / `credHelpers`) are deliberately not executed. Use a file containing inline auth instead; empty helper-backed credentials produce a clear error. Registry tokens are not logged. The file must not be committed. A Docker socket mount grants extensive host privileges. This PR does **not** implement remote digest prechecks: the standalone update engine still pulls before comparing local image identities.

---

## Registres privés (FR)

Pour GHCR ou un autre registre privé, montez un `config.json` Docker dédié contenant les identifiants dans `auths` et définissez `SYSTOWER_DOCKER_AUTH_CONFIG` avec son chemin dans le conteneur. Utilisez un token de lecture seule, des droits de fichier restrictifs et **ne commitez jamais ce fichier**. Le champ `auth` est encodé en Base64, **pas chiffré**.

Les helpers de mots de passe Docker Desktop ne sont pas exécutés. Sans identifiants correspondants, les images publiques peuvent toujours être récupérées anonymement. Cette fonction n'effectue pas encore de vérification distante de digest.
