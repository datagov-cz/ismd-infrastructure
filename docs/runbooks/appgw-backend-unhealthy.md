# appgw-backend-unhealthy

**Trigger**: `UnhealthyHostCount` > 0 average over 5 min on the shared AppGW. Sev1 paging.

**What it means**: one or more backend pools have failed health probes. Users likely seeing errors.

**First look**:
```bash
az network application-gateway show-backend-health \
  -n ismd-app-gateway -g ismd-shared-global \
  --query "backendAddressPools[].{pool:backendAddressPool.id, servers:backendHttpSettingsCollection[].servers[]}" -o json
```
Find the pool with `health: Unhealthy` and read `healthProbeLog`.

**Common causes**:
- Backend Container App scaled to 0 or down (check companion `replicas-zero` alert).
- Probe path returns non-200 (recent path change in the app?).
- Anticipatory pool pointing at a non-existent app — should be in the `appgw_excluded_backend_settings` list; if not, add it.
- AppGW SSL/listener issue (recent shared-global change?).

**Resolution**: restart the app, fix the probe path, or add the pool to the exclusion list if intentional.
