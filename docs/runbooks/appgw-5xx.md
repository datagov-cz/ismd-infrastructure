# appgw-5xx

**Trigger**: `ResponseStatus` with `HttpStatusGroup = 5xx` total > 5 in 5 min. Sev2 quiet.

**First look**:
1. AppGW access logs in `ismdmonglobal/insights-logs-applicationgatewayaccesslog/` (90-day retention). Look at `requestUri_s`, `httpStatus_d`, `backendPoolName_s`, `serverStatus_s` for the failing requests.
2. Cross-check with companion per-app `http-5xx` alerts — if a Container App is also firing, the issue is app-side, not gateway-side.

**Common causes**:
- Backend Container App returning 5xx (cascade from app issue).
- AppGW listener misconfiguration (recent rule/path change).
- Backend pool unhealthy (companion alert should also fire).
- Cert / TLS handshake failure between AppGW and backend.

**Resolution**: address at the right layer — app, AppGW config, or backend cert.
