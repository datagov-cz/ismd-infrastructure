# Security Scanning — Runbook

Scope: Trivy (image CVE scanning) and CodeQL (source SAST) across the four app repos, plus the reusable Trivy workflow owned by this infra repo.

---

## What Runs Where

| Tool | Type | Scans | Owned by | Findings land in |
|---|---|---|---|---|
| **Trivy** | Image CVE (SCA) | Built Docker images in GHCR | Infra (reusable) + per-app (stub) | App repo → Security → Code scanning |
| **CodeQL** | Source SAST | JS/TS, Java source | Per-app | App repo → Security → Code scanning |
| **Checkov** | IaC | Terraform in this repo | Infra | This repo → Security → Code scanning |

Checkov is planned but not yet implemented.

---

## File Inventory

| Repo | File | Purpose |
|---|---|---|
| `ismd-infrastructure` | `.github/workflows/trivy-reusable.yml` | Reusable Trivy scanner. Single source of truth for scanner config. |
| `ismd-validator-frontend` | `.github/workflows/trivy.yml` | Stub — calls reusable for validator-frontend images |
| `ismd-validator-frontend` | `.github/workflows/codeql.yml` | CodeQL JS/TS |
| `ismd-tool-frontend` | `.github/workflows/trivy.yml` | Stub — tool-frontend images |
| `ismd-tool-frontend` | `.github/workflows/codeql.yml` | CodeQL JS/TS |
| `ismd-validator-backend` | `.github/workflows/trivy.yml` | Stub — validator-backend images |
| `ismd-validator-backend` | `.github/workflows/codeql.yml` | CodeQL Java (replicates mvnw build incl. common library) |
| `ismd-tool-backend` | `.github/workflows/trivy.yml` | Stub — tool-backend images |
| `ismd-tool-backend` | `.github/workflows/codeql.yml` | CodeQL Java |

---

## Trivy — Triggers

Per-app stubs wire up the following triggers. The scanner logic itself is centralized in the reusable.

| Event | `scan-dev` job | `scan-main` job | Reason |
|---|---|---|---|
| `Build Docker on Dev` succeeds | ✅ | ❌ | New dev image scanned within minutes |
| `Build Docker on Main` succeeds | ❌ | ✅ | New prod-bound image scanned within minutes |
| Schedule (Mondays 07:00 UTC) | ✅ | ✅ | CVE-feed drift — new CVEs may land for unchanged images |
| Manual dispatch (`dev`) | ✅ | ❌ | Targeted re-scan |
| Manual dispatch (`main`) | ❌ | ✅ | Targeted re-scan |
| Manual dispatch (`both`) | ✅ | ✅ | Full re-scan |

**Image taxonomy** (per `reusable-docker-build.yml` in each app repo):

- `dev` branch → `ghcr.io/datagov-cz/<repo>-dev:latest` → deployed to dev
- `main` branch → `ghcr.io/datagov-cz/<repo>:latest` → deployed to test, then prod

Both variants are scanned. Findings are deduplicated in the Security tab per `category:` — Trivy uses `trivy-image`.

### Important quirk

`workflow_run` triggers **only fire when the workflow file lives on the repo's default branch**. On merge into `dev`, the new `trivy.yml` won't react to `Build Docker on *` events until it's also on `main`. Cron and manual dispatch work either way.

---

## CodeQL — Triggers

- `push` to `dev` or `main`
- `pull_request` targeting `dev` or `main`
- Schedule: Mondays 06:00 UTC

CodeQL scans source, not images, so branch is the right axis (not image variant).

---

## Blocking vs Non-Blocking

**Default everywhere: non-blocking.** Findings populate the Security tab; workflows always succeed. This is the right baseline — flipping to blocking before you have a clean baseline just deadlocks PRs on pre-existing issues.

### Trivy — How to Make a Scan Blocking

**Option A — One-off blocking run (manual, for testing a specific fix):**

1. Go to the app repo → Actions → **Trivy Image Scan** → **Run workflow**.
2. Pick `image_variant` (`dev`, `main`, or `both`).
3. **Uncheck** the `soft_fail` checkbox.
4. Run. Scan fails the job on any HIGH/CRITICAL finding.

The `soft_fail` input defaults to checked (non-blocking). Auto-triggered runs (`workflow_run`, `schedule`) **always** run non-blocking regardless of this input — by design, so a fresh CVE disclosure doesn't silently turn every deploy red overnight.

**Option B — Permanent blocking for all repos (via reusable workflow default):**

Edit [`../.github/workflows/trivy-reusable.yml`](../.github/workflows/trivy-reusable.yml), change the default on the `soft_fail` input:

```yaml
soft_fail:
  required: false
  type: boolean
  default: false    # <-- was true
```

This flips **all four app repos** at once, on their next scheduled or workflow_run-triggered scan. Only do this once Security tab baselines are clean (zero open findings across all repos), otherwise all four repos will have red Trivy checks simultaneously.

### CodeQL — How to Make a Scan Blocking

CodeQL's `analyze` action never fails the job on findings — it uploads SARIF and exits green. Blocking is controlled **at the repo level, not in the workflow file**, via branch protection:

1. Repo → Settings → Branches → Add (or edit) rule for `main` (and/or `dev`).
2. Enable **Require status checks to pass before merging**.
3. Add `Analyze (javascript-typescript)` (for frontends) or `Analyze (java)` (for backends) as a required check.
4. Optionally enable **Require branches to be up to date** and **Include administrators**.

From that moment, PRs introducing new CodeQL findings fail the required check and can't be merged. Existing findings on the base branch remain visible in the Security tab but don't block — only new code introducing new findings does.

Recommended rollout: set this up **after** the baseline is triaged (existing findings either fixed or dismissed with reason in the Security tab UI).

### Summary Table

| Tool | Default | One-off blocking | Permanent blocking |
|---|---|---|---|
| Trivy | Non-blocking | Manual dispatch with `soft_fail` unchecked | Flip default in `trivy-reusable.yml` |
| CodeQL | Non-blocking (job always green) | N/A — action doesn't fail | Branch protection rule: require `Analyze` check |

---

## Operating Procedures

### Triaging a new Trivy finding

1. Open the app repo → Security → Code scanning → filter by `trivy-image`.
2. Click the finding. Note the package, installed version, fix version, severity.
3. Decide:
   - **Base-image finding** (alpine/musl/openssl/libpng/zlib etc.) → devops fixes in the Dockerfile. Usually a base tag bump.
   - **App-dep finding** (axios, tomcat, spring-core, etc.) → file an issue for the FE/BE team with the finding link.
   - **False positive / inapplicable** → dismiss with reason in the UI (dismissals persist across runs).

### Triaging a new CodeQL finding

1. Open the app repo → Security → Code scanning → filter by language.
2. Click the finding. CodeQL shows the exact file/line and a data flow if applicable.
3. Decide:
   - **Real bug** → file an issue for the owning team.
   - **Won't fix / test code / intentional** → dismiss with reason.

### Rolling the reusable Trivy workflow forward

The stub workflows pin to `@dev` (matches existing `terraform.yml` convention). When you edit `trivy-reusable.yml`:

- Push to `dev` → stubs pick up changes immediately.
- Once stable, consider switching stubs to a version tag (`@v1`) for explicit rollouts.

### When a team fixes a CVE and redeploys

1. Team merges fix → builds new image → `Build Docker on *` succeeds.
2. `workflow_run` fires → Trivy rescans the fresh image within minutes.
3. Security tab auto-dismisses findings that no longer appear in the new scan (by CVE ID + package).
4. If a finding doesn't auto-clear, verify the installed version in the new image actually changed — it may be a sibling dep transitively pulling in the old version.

---

## Local Scanning (Devops Only)

### Trivy (ad-hoc recon)

Run under WSL bash with Docker Desktop active:

```bash
for img in ismd-tool-backend-dev ismd-tool-frontend-dev ismd-validator-backend-dev ismd-validator-frontend-dev; do
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$HOME/.cache/trivy:/root/.cache/" \
    aquasec/trivy:latest image \
    --severity CRITICAL,HIGH --ignore-unfixed --scanners vuln --quiet \
    "ghcr.io/datagov-cz/${img}:latest" > "${img}.txt" 2>&1
done
```

GHCR images are public — no auth needed.

### CodeQL (not installed locally)

CodeQL is CI-only in this project. The CLI bundle is ~700 MB and Java DB creation runs a full Maven build. Use the GitHub Actions runs for CodeQL results; the Security tab dedupes and formats better than local SARIF anyway.

---

## Known Limitations / Gotchas

- **Trivy scans `:latest` only.** If a specific versioned image needs ad-hoc scanning, dispatch-run with a local edit or pull the tagged image and run Trivy manually.
- **`workflow_run` default-branch requirement** (see above) — first rollout requires merging to the default branch before auto-trigger works.
- **Trivy DB rate limits on GHCR** — mitigated by pulling DB from AWS public ECR (`TRIVY_DB_REPOSITORY` env in the reusable).
- **CodeQL Java build reuses `mvnw`** — requires `GITHUB_TOKEN` with `packages: read` (already set in the workflows) to pull `ismd-validator-common` from GH Packages.
