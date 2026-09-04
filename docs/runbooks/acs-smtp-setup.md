# Runbook: ACS Email SMTP setup for Keycloak

Purpose: stand up the out-of-band pieces ACS SMTP needs that terraform cannot create
(Entra app registration, client secret, RBAC role assignment, SMTP username mapping),
then wire Keycloak's `ismd` realm to send email through ACS.

Related: `modules/shared_global/acs_email.tf`, `keycloak-config/` (the realm-in-IaC work).

## Why this is manual

The terraform SP is **Contributor only**. It can create the ACS resources
(`Microsoft.Communication/*`) but it **cannot**:
- create Entra (Azure AD) app registrations (no Graph permission), or
- create role assignments (`Microsoft.Authorization/roleAssignments/write`).

So steps 1–3 below are done by a human with Entra app-registration rights + Owner/UAA
on the ACS scope. Everything in terraform (`acs_email.tf`) must be applied first.

Also note: the `Microsoft.Communication` resource provider must be registered on the
subscription before the first ACS apply (the Contributor terraform SP can't self-register
it — the apply 409s with `MissingSubscriptionRegistration`). One-time, per subscription:
```bash
az provider register --namespace Microsoft.Communication   # wait until 'Registered'
```

## Prerequisites

- `acs_email.tf` applied in shared-global. Provisioned values (2026-05-29):
  - ACS resource: `ismd-acs` in resource group `ismd-shared-global`
  - Managed sender (works once SMTP auth is set up, no client DNS):
    `DoNotReply@90dda272-e6e0-4ee1-b46c-0e9149ce7bda.azurecomm.net`
  - SMTP host: `smtp.azurecomm.net`
  - Re-fetch anytime: `terraform output acs_name | acs_managed_from_address | acs_smtp_host`
- Tenant ID: `5b6b85cd-44ef-4d66-86d4-603dd2160780`

### ACS resource layout (so the naming makes sense)

| Resource | Role |
|----------|------|
| `azurerm_communication_service.dia` (`ismd-acs`) | Top-level platform. Hosts the SMTP relay endpoint, the **SMTP Usernames** blade, connection strings, and the RBAC scope ("Communication and Email Service Owner" goes on this). |
| `azurerm_email_communication_service.dia` (`ismd-email`) | Email-only sub-platform. **Doesn't send** — it's the container that owns sender domains. |
| `azurerm_email_communication_service_domain.managed` (`AzureManagedDomain`, `90dda272-…azurecomm.net`) | Auto-verified free sender domain. Used for DEV/TEST. |
| `azurerm_email_communication_service_domain.custom` (`auth.dia.gov.cz`, CustomerManaged) | PROD sender domain. Unverified until the client publishes DNS. |
| `azurerm_communication_service_email_domain_association.managed` | The link between the Communication Service and a sender domain. Required for the platform to send from it. Custom-domain association is gated on `acs_custom_domain_verified`. |

So: `ismd-acs` is *who sends*, `ismd-email` *owns the domains*, the two domain resources *are the senders*, and the association *connects them*.

---

## Step 1 — Entra app registration + client secret

Portal → **Microsoft Entra ID** → **App registrations** → **New registration**.
- Name: `ismd-acs-smtp`
- Supported account types: **Single tenant**
- Redirect URI: leave blank
- Register.

Capture from the Overview blade:
- **Application (client) ID** → call it `APP_ID`
- **Directory (tenant) ID** → `5b6b85cd-44ef-4d66-86d4-603dd2160780`

Then **Certificates & secrets** → **New client secret**:
- Description: `acs-smtp`
- Expiry: 24 months (max). **Record the expiry date** for rotation (see "Rotation").
- **Copy the secret VALUE immediately** (shown once). This is the SMTP password.

> The secret value contains special characters (`~`, etc.). Keycloak's SMTP password
> field accepts them, but never paste it into a PR, plan output, or chat.

---

## Step 2 — Assign the ACS role to the app

The app must hold **Communication and Email Service Owner** on the ACS resource.

Portal: `ismd-acs` → **Access control (IAM)** → **Add role assignment** →
role **Communication and Email Service Owner** → assign to the `ismd-acs-smtp` app
registration (search by name) → Review + assign.

Or CLI (requires Owner/UAA on the scope):
```bash
ACS_ID=$(terraform -chdir=infrastructure/shared-global output -raw acs_id)
APP_OBJ=$(az ad sp list --display-name ismd-acs-smtp --query "[0].id" -o tsv)
az role assignment create \
  --assignee-object-id "$APP_OBJ" \
  --assignee-principal-type ServicePrincipal \
  --role "Communication and Email Service Owner" \
  --scope "$ACS_ID"
```

---

## Step 3 — Create the SMTP username in ACS

Portal: `ismd-acs` → **SMTP Usernames** (left blade) → **+ Add** → select the
`ismd-acs-smtp` Entra application → Add.

This yields the SMTP username. Format (note: separators may be `.` or `|`):
```
ismd-acs.<APP_ID>.5b6b85cd-44ef-4d66-86d4-603dd2160780
```
Copy the exact string the portal shows — don't hand-assemble it.

---

## Step 4 — (Optional) stash credentials in Key Vault

The authoritative copy lives in `infrastructure/.env.<env>` as
`TF_VAR_smtp_username` / `TF_VAR_smtp_password` (and inside the keycloak-config
state once applied). KV is a secondary backup for rotation/recovery if `.env.<env>`
is lost. KV `ismd-keyvault` already exists.
```bash
az keyvault secret set --vault-name ismd-keyvault --name keycloak-smtp-username --value "<SMTP username from step 3>"
az keyvault secret set --vault-name ismd-keyvault --name keycloak-smtp-password --value "<secret value from step 1>"
```
(Skip if you lack KV data-plane access — `.env.<env>` is what terraform actually reads.)

---

## Step 5 — Configure Keycloak `ismd` realm SMTP via `keycloak-config`

The `ismd` realm is in IaC now (`keycloak-config/`, workspaces `dev` and `test`;
PROD will join once the tool deploys there). The realm's SMTP block is wired
through the module's `smtp_*` variables — no admin-console clicks.

1. Put the credentials from Steps 1 + 3 into `infrastructure/.env.<env>`
   (gitignored), alongside the existing `TF_VAR_tool_keycloak_admin_password`:
   ```bash
   TF_VAR_smtp_username=<SMTP username from Step 3>
   TF_VAR_smtp_password=<client-secret value from Step 1>
   ```
   Do this for `.env.dev` and `.env.test`.
2. In `keycloak-config/dev.tfvars` (then `test.tfvars`), flip SMTP on and enable
   the email-driven flows you want:
   ```hcl
   smtp_enabled           = true
   smtp_from              = "DoNotReply@<guid>.azurecomm.net"   # from `terraform output acs_managed_from_address`
   reset_password_allowed = true   # password-reset emails for provisioned users
   # verify_email         = true   # only if you also want email verification
   ```
   `smtp_from_display_name` defaults to `"DIA – Digitální informační agentura"`;
   override in tfvars if needed. `smtp_starttls` defaults to `true` and
   `smtp_port` to `587` — leave them.
3. Apply per env:
   ```bash
   cd infrastructure/keycloak-config
   ../terraw.sh switch dev && ../terraw.sh apply
   ../terraw.sh switch test && ../terraw.sh apply
   ```
   The plan should update `keycloak_realm.ismd` in-place (adds the `smtp_server`
   block + flips `reset_password_allowed`).
4. Verify in the Keycloak admin console: realm `ismd` → Realm settings → Email
   shows the values and **Test connection** succeeds.

Decision reminder: `registration_allowed` stays **false** (accounts are
provisioned, not self-signup). Email here primarily unblocks **password reset**
for provisioned users — and `verify_email` if you choose to enable it.

---

## Step 6 — End-to-end verification

1. Create/flag a test user in `ismd`, trigger **Reset password** (or enable
   "Verify email" required action) so Keycloak sends a real message.
2. Confirm delivery. **Test Czech consumer providers specifically**: `@seznam.cz`,
   `@email.cz` (conservative filters), plus one `@gmail.com`.
3. Check headers: SPF/DKIM should pass. Managed domain is pre-aligned; custom domain
   only after Step 7.

---

## Step 7 — Custom domain (`auth.dia.gov.cz`) cutover — later, PROD sender

1. Records the client must publish (from `terraform output acs_custom_domain_verification_records`,
   2026-05-29 — re-fetch to confirm before sending, values are tied to the live resource):

   | Type | Host/Name | Value |
   |------|-----------|-------|
   | TXT | `auth.dia.gov.cz` | `ms-domain-verification=0f6ab27f-6d89-4ac2-b061-af1afa60c287` |
   | TXT (SPF) | `auth.dia.gov.cz` | `v=spf1 include:spf.protection.outlook.com -all` |
   | CNAME | `selector1-azurecomm-prod-net._domainkey` | `selector1-azurecomm-prod-net._domainkey.azurecomm.net` |
   | CNAME | `selector2-azurecomm-prod-net._domainkey` | `selector2-azurecomm-prod-net._domainkey.azurecomm.net` |

   **DMARC: ACS emits none** (the `dmarc` list is empty). Add one manually for monitoring —
   start permissive, tighten later:

   | Type | Host/Name | Value |
   |------|-----------|-------|
   | TXT | `_dmarc.auth.dia.gov.cz` | `v=DMARC1; p=none; rua=mailto:<monitored-mailbox>` |

   SPF caveat: if `auth.dia.gov.cz` (or a parent) already has an SPF record, merge — don't
   add a second SPF TXT (multiple SPF records = permerror).
2. Wait for propagation; ACS portal shows the domain **Verified**.
3. Flip the toggle and apply to associate it:
   ```hcl
   # shared-global/terraform.tfvars (or module input)
   acs_custom_domain_verified = true
   ```
4. Update the realm **From** to `noreply@auth.dia.gov.cz`. Re-run Step 6, re-check
   DKIM alignment against the custom domain.

---

## Rotation

The Entra client secret expires (you set 24 months in Step 1). An expired secret =
**silent** password-reset breakage.
- Add a calendar reminder ~1 month before expiry.
- To rotate: new client secret on the same app → update `TF_VAR_smtp_password` in
  `infrastructure/.env.<env>` (and the KV copy if you keep one) → re-apply
  `keycloak-config` per env (`../terraw.sh switch <env> && ../terraw.sh apply`) →
  Test connection in the Keycloak admin console.

## Gotchas

- **SMTP egress**: confirm the Container Apps environment allows outbound TCP 587. If
  email hangs, exec into the Keycloak container and `nc -vz smtp.azurecomm.net 587`.
- **Exact SMTP host**: ACS may surface a region-specific host; trust the portal value
  over the `smtp.azurecomm.net` default in the terraform output.
- **One ACS, all envs**: a misconfigured TEST sender can dent the shared domain's
  reputation. Keep the managed domain for lower envs; reserve the custom domain for PROD,
  or use distinct From addresses.
