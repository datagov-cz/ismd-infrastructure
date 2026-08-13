#!/usr/bin/env bash
set -euo pipefail

# ---- config (DEV) ----
RG="ismd-tool-dev"
APP="ismd-tool-fuseki-dev"
STORAGE_ACCT="ismdtoolfusekidev"
SHARE="fuseki-data"
DATASET="ismd-tool-dataset"

echo "This STOPS $APP and DELETES all TDB2 + Lucene data for '$DATASET'."
read -p "Type 'WIPE DEV' to continue: " confirm
[ "$confirm" = "WIPE DEV" ] || { echo "aborted"; exit 1; }

# ---- 1. scale to 0 replicas (deactivate, NOT restart — restart overlaps and keeps the lock) ----
REV=$(az containerapp revision list -n "$APP" -g "$RG" \
        --query "[?properties.active].name | [0]" -o tsv)
echo "Active revision: $REV — deactivating..."
az containerapp revision deactivate -n "$APP" -g "$RG" --revision "$REV"

echo "Waiting for replicas to reach 0..."
for i in $(seq 1 30); do
  N=$(az containerapp replica list -n "$APP" -g "$RG" --revision "$REV" \
        --query "length(@)" -o tsv 2>/dev/null || echo 0)
  echo "  replicas: $N"
  [ "$N" = "0" ] && break
  sleep 10
done
[ "$N" = "0" ] || { echo "still $N replicas — aborting before delete"; exit 1; }

# ---- 2. delete data (storage key needed for file ops) ----
KEY=$(az storage account keys list -n "$STORAGE_ACCT" -g "$RG" \
        --query "[0].value" -o tsv)

echo "Deleting TDB2 + Lucene files..."
az storage file delete-batch --account-name "$STORAGE_ACCT" --account-key "$KEY" \
  --source "$SHARE" --pattern "tdb2/$DATASET/*"
az storage file delete-batch --account-name "$STORAGE_ACCT" --account-key "$KEY" \
  --source "$SHARE" --pattern "lucene/$DATASET/*"

# remove now-empty dirs so TDB2 re-inits fresh (bottom-up; ignore if already gone)
for d in "tdb2/$DATASET/Data-0001" "tdb2/$DATASET" "lucene/$DATASET"; do
  az storage directory delete --account-name "$STORAGE_ACCT" --account-key "$KEY" \
    --share-name "$SHARE" --name "$d" 2>/dev/null || true
done

# ---- 3. bring Fuseki back (boots clean/empty) ----
echo "Reactivating $REV..."
az containerapp revision activate -n "$APP" -g "$RG" --revision "$REV"
echo "Done. Watch boot:  az containerapp logs show -n $APP -g $RG --follow"
