# Inputs for the shared-global root (the App Gateway + WAF + global Key Vault).
#
# COMMITTED ON PURPOSE. This file contains no secrets — only public DNS names
# and Container Apps environment domains — and it is load-bearing: every
# variable it sets defaults to "" in variables.tf, and the App Gateway's backend
# pools and listener host names are built from them.
#
# Without this file, `terraform plan` here proposes emptying EVERY backend
# address pool and blanking EVERY listener host_name — dev, test and prod — and
# reports it as "0 to add, 2 to change, 0 to destroy". The destroy count is not
# the signal; read the attribute lines.
#
# Values are the applied state as of 2026-08-31, cross-checked against
# `az containerapp env list`. The domains change only if a Container Apps
# environment is deleted and recreated; if that happens, re-read them from
# `az containerapp env list --query "[].{name:name,domain:properties.defaultDomain}"`
# and update here BEFORE planning.

container_app_environment_domain_dev  = "livelydesert-e8731aef.germanywestcentral.azurecontainerapps.io"
container_app_environment_domain_test = "mangodune-bfe5a576.germanywestcentral.azurecontainerapps.io"
container_app_environment_domain_prod = "ashypebble-1dbef699.germanywestcentral.azurecontainerapps.io"

# Public hostnames, punycode exactly as held in state:
#   test = slovník-test.dia.gov.cz
#   prod = slovník.gov.cz
dev_hostname  = "oha03.dia.gov.cz"
test_hostname = "xn--slovnk-test-scb.dia.gov.cz"
prod_hostname = "xn--slovnk-7va.gov.cz"
