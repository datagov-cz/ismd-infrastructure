# ghcr-pull-failure

**Trigger**: any Container App console log line matching `failed to pull image | ImagePullBackOff | ErrImagePull` in a 10-min window. Sev2 quiet.

**What it means**: GHCR pull is failing. New replicas can't start; running replicas keep running but autoscale/rollout is blocked.

**First look**:
1. Container App System logs → `PullingImage` / `Failed` events. What's the error message?
2. Image tag — does it still exist on GHCR? Try `curl -sI https://ghcr.io/v2/datagov-cz/<image>/manifests/<tag>` — should return 200 (with anonymous token) for public images.
3. Recent GitHub Actions workflow — did the CI push the tag we expect?

**Common causes (current setup: GHCR images are PUBLIC, no PAT in Container App config)**:
- **Tag deleted / never pushed**: image cleanup workflow purged an old tag we're still pinned to, or CI never pushed the new tag. Most common.
- **Repo visibility changed to private**: would suddenly require auth. Check on the GitHub repo settings. If we ever go private, we'd need to add a `registries` block to each Container App + a PAT secret.
- **GHCR-side outage**: rare; check https://www.githubstatus.com/.

**Resolution**:
- Repoint to a tag that exists (`az containerapp update --image ghcr.io/.../app:<tag>`).
- If repo went private, wire a GHCR PAT into Container App `registries` config (terraform change — not currently scaffolded).
- For GHCR outage, wait it out.

**Note**: this project uses **public GHCR images** — no `registry_password` secret is configured on Container Apps. If you see auth errors in pull logs, that means the repo visibility flipped or a public-anonymous-token quota was hit (rare).
