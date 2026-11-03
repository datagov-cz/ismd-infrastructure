# postgres-restore-one-database

**When**: one database on `ismd-tool-postgres-<env>` is damaged. If the whole server is lost, use Azure
point-in-time restore to a new server instead (7 days on dev and test).

**Status**: rehearsed on dev 2026-11-03 for `ismd_tool_db` and `keycloak_db`, including the apps on
restored data and the way back. Not rehearsed on test. `scripts/postgres-restore-drill.sh` automates
these steps for dev, and is hardcoded to dev.

**What you need**:
- Contributor on the subscription, which lets `az` fetch the storage key.
- Your IP on the server's firewall.
- Read access to `ismd-kv-<env>`.
- `pg_restore` 16 or newer.

**Where things are**:
- Dumps: storage account `ismdpgbackup<env>`, containers `weekly` (14 days) and `monthly` (90 days),
  named `<db>-<yyyy-mm-dd>.dump.enc`. Written Sundays 01:30 UTC by job `ismd-pg-backup-<env>`.
- Passphrase: `ismd-kv-<env>/pg-backup-encryption-key`. **There is no other copy, and without it the
  dumps are unreadable.** If the key was rotated after the dump was taken, use the older version
  (`az keyvault secret list-versions`).
- Admin password: `ismd-kv-<env>/postgres-password`. Pass secrets through env vars, not arguments.

## Steps

The restore goes beside the live database and swaps by rename, so there is a way back at every step.

1. Create `<db>_restore_test` with the live database's owner (`ismd_tool_app`, `ismd_keycloak_app`),
   then `REVOKE CONNECT ON DATABASE ... FROM PUBLIC`.
2. Restore into it, serially. The job pipes `pg_dump`, so `pg_restore -j` does not work:
   ```
   openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass env:BACKUP_KEY -in <file> \
     | pg_restore -h <host> -U ismdadmin -d <db>_restore_test --no-acl
   ```
   A `pg_restore` 17+ client against Postgres 16 reports one error,
   `unrecognized configuration parameter "transaction_timeout"`, and exits 1. That one is harmless.
   Any other error is real.
3. Compare schema and row counts with the damaged database. To compare contents, hash the rows in each:
   `select md5(string_agg(x, chr(10) order by x)) from (select t::text x from <table> t) s`.
4. Stop the consuming app with `az containerapp revision deactivate`. **Keycloak down means login is
   down for the whole stack.** Check replicas per revision with `--revision`: without it the list can be
   empty while pods still run. Replicas took 40 s to 2.5 min to go.
5. Rename `<db>` to `<db>_old`, then `<db>_restore_test` to `<db>`. This needs no open connections.
6. Start the app with a new revision (`az containerapp update --revision-suffix <suffix>`), then **at
   once deactivate the old revision, because the update reactivates it**. Keycloak took 97 s and the
   backend about 78 s, followed by a short gateway 502.
7. For `ismd_tool_db`, run the reconciler (below). For `keycloak_db`, log in directly and through CAAIS.
8. Keep `<db>_old` until you are sure, then drop it. To go back, stop the app and rename the other way.

## After restoring `ismd_tool_db`

**The app looks normal while it is wrong.** Postgres and Fuseki/TDB2 share no transaction, and this
restores only Postgres. Everything written since the dump is out of step:

| Since the dump | In the UI | Reconciler |
|---|---|---|
| Concept created | Listed, but the link has no slug, so a 404 | `RDF_ORPHAN` |
| Concept deleted | Not listed. Postgres has a row nothing shows | `PG_MISSING_RDF` |
| Slovník created | Not listed. Its data stays in Fuseki | `GRAPH_ORPHAN`, plus `RDF_ORPHAN` per concept |

Run the reconciler with an `ADMIN` token: `POST /popisujeme/be/api/admin/reconciler/run`. It only reports.
Dev already has known orphans, so compare with an earlier report rather than expecting zero.

Recreating an orphaned concept under the same name repaired it in the rehearsal (tested on an empty
concept). See `ismd-tool-backend/docs/PG_TDB2_CONSISTENCY.md`.

## Traps

- **Anything written since the dump is lost.** Dumps can be up to a week old.
- **Restored sequences reissue IDs** already used since the dump, to different rows.
- **The target server must already have the app roles**, because the restore recreates ownership.
  Restoring into another environment needs the same role names: `db/user-separation/README.md`.
- **`--no-acl`** turns `ismd_schema`'s explicit permission list into the default. Effective permissions
  are the same. The dump's other ACLs are platform grants on `pg_catalog` that a non-admin can't replay.
- **Restarting Fuseki**: a new revision can't get the TDB2 lock while the old one holds it. Lock errors
  for a few minutes after the old one stops are normal.
- **The backup job can run once per day.** Names carry only the date and uploads don't overwrite.
- `keycloak_db` holds personal data and password hashes, so treat a decrypted dump like a secret.
- Test has no `ismd_ai` dump. Prod has no backup job.
