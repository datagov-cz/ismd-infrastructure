# appgw-5xx

**Trigger**: `ResponseStatus` with `HttpStatusGroup = 5xx` total > 5 in 5 min. Sev2 quiet.

**First look**:
1. Run `scripts/investigate-appgw-5xx.sh "<alert time as shown, Europe/Prague>"` — it converts to UTC, pulls the right hour's access-log blob (account-key auth, no RBAC role needed), and prints the failing requests: URL, backend status, response time, error_info, user-agent. Add `--firewall` to also dump WAF blocks. This replaces the manual blob-download + jq below.
2. Manual fallback: AppGW access logs in `ismdmonglobal/insights-logs-applicationgatewayaccesslog/` (90-day retention). Fields are under `.properties` (`requestUri`, `httpStatus`, `serverStatus`, `timeTaken`) EXCEPT `backendSettingName`/`backendPoolName` which are top-level. `serverStatus` = the code the backend returned.
2. Cross-check with companion per-app `http-5xx` alerts — if a Container App is also firing, the issue is app-side, not gateway-side.

**Common causes**:
- Backend Container App returning 5xx (cascade from app issue).
- AppGW listener misconfiguration (recent rule/path change).
- Backend pool unhealthy (companion alert should also fire).
- Cert / TLS handshake failure between AppGW and backend.

**Resolution**: address at the right layer — app, AppGW config, or backend cert.
