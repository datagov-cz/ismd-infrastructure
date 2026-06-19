# availability

**Trigger**: AI standard web test failing in ≥ 2 of 2 EMEA POPs (Amsterdam + London) for 5+ min. Sev1.

**Endpoints monitored**:
- `https://oha03.dia.gov.cz/validujeme` — validator FE
- `https://oha03.dia.gov.cz/popisujeme` — tool FE
- `https://oha03.dia.gov.cz/popisujeme/auth/realms/<realm>/.well-known/openid-configuration` — Keycloak

**First look**:
1. Manual probe: `curl -sIL <url>` — does it return 200?
2. App Insights → Availability → drill into failing test → see "result message" per probe (e.g. SSL handshake failure, timeout, status code mismatch).
3. AppGW backend health: `az network application-gateway show-backend-health -n ismd-app-gateway -g ismd-shared-global`.

**Common causes**:
- **"The function requested is not supported"** = TLS-renegotiation issue. We hit this once; fix was setting explicit `ssl_policy AppGwSslPolicy20220101` on AppGW. Should NOT recur.
- **Status code mismatch** = backend returning non-200 (cascade from app issue).
- **SSL cert expired** = `ssl_cert_remaining_lifetime` is set to 7 days; if cert expires the test fails. Rotate cert.
- **Timeout** = AppGW slow / backend slow / cold-start spike.

**Resolution**: address the underlying probe failure. Test only resolves when both POPs pass.
