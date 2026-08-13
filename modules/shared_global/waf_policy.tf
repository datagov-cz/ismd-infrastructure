# Application Gateway WAF Policy
# Provides rate limiting + Microsoft DRS 2.2 protection for ismd-app-gateway.
# Associated gateway-wide via firewall_policy_id in appgw_resource.tf (applies
# to every listener / hostname: validator + tool apps).
#
# IMPORTANT — Azure behavior:
#   * A RateLimitRule only ENFORCES (blocks) when mode = "Prevention". In
#     "Detection" mode the WAF logs matches but blocks nothing, including the
#     rate-limit rule.
#   * mode is policy-wide: it governs the OWASP managed rules too. There is no
#     per-ruleset "Detection" action on Application Gateway WAF (unlike Front
#     Door), so enabling rate-limit blocking necessarily puts OWASP into
#     blocking as well. Tune OWASP false positives via `rule_group_override`
#     / `exclusion` blocks under managed_rule_set as they surface in the logs.

resource "azurerm_web_application_firewall_policy" "appgw" {
  name                = "ismd-waf-policy"
  resource_group_name = azurerm_resource_group.shared_global.name
  location            = azurerm_resource_group.shared_global.location

  policy_settings {
    enabled = true
    mode    = var.waf_mode

    # App's max file upload is 10 MB; allow 15 MB so legitimate uploads aren't
    # blocked by the WAF before reaching the app. (Default would be 100 MB, but
    # set explicitly to keep the limit intentional and tight.)
    file_upload_limit_in_mb = 15

    # Non-file request body limit left at the Azure default of 128 KB — ample
    # for the app's JSON/form POSTs and the tighter, safer default.
  }

  # Rate limiting: at most `waf_rate_limit_threshold` requests per client per
  # `waf_rate_limit_duration` window; requests over the limit are blocked.
  # The match condition matches all traffic (every request URI contains "/"),
  # so the limit applies gateway-wide.
  #
  # Grouped by ClientAddrXFFHeader, NOT ClientAddr: all end-user traffic reaches
  # this gateway via the client's nginx reverse proxy (single TCP source IP), so
  # ClientAddr would collapse the entire userbase into one bucket and throttle
  # everyone together (observed: mass 429s on legit calls like
  # /popisujeme/api/backend/api/user/me → "unauthorized after login"). Grouping
  # by the X-Forwarded-For IP keys the limit on the real per-user client address.
  #
  # PREREQUISITE / trust boundary: XFF is client-supplied, so this is only sound
  # if the client's nginx sets X-Forwarded-For to the true client IP in a
  # non-spoofable way (overwrite with $remote_addr, or sanitize any inbound XFF).
  # If nginx blindly appends to a client-sent XFF, a caller could poison/evade
  # the per-IP grouping. Confirm nginx XFF handling before trusting this for
  # abuse mitigation.
  custom_rules {
    name                 = "RateLimitPerClientIp"
    priority             = 10
    rule_type            = "RateLimitRule"
    action               = "Block"
    rate_limit_duration  = var.waf_rate_limit_duration
    rate_limit_threshold = var.waf_rate_limit_threshold
    group_rate_limit_by  = "ClientAddrXFFHeader"

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator           = "Contains"
      negation_condition = false
      match_values       = ["/"]
    }
  }

  # Scoped WAF bypass for the Keycloak admin console. The new admin console saves
  # realm settings via JSON PUTs to /admin/realms/<realm>/ui-ext whose bodies trip
  # DRS false positives (930120 LFI "OS File Access Attempt" + 932130 RCE "Unix
  # Shell Expression" → anomaly score 10 → 949110 blocks with 403). This path is
  # already gated by Keycloak admin auth, so an Allow rule scoped to it lets those
  # requests skip managed-rule evaluation while DRS stays fully active on the
  # public validator + tool app surfaces. Priority 20 runs AFTER the rate-limit
  # rule (priority 10), so rate limiting still applies; the Allow match then stops
  # further managed-rule processing for the matched request.
  custom_rules {
    name      = "AllowKeycloakAdmin"
    priority  = 20
    rule_type = "MatchRule"
    action    = "Allow"

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator           = "BeginsWith"
      negation_condition = false
      match_values       = ["/popisujeme/auth/admin/"]
    }
  }

  # Blocked requests return different status codes by rule type: the custom
  # RateLimitRule Block returns HTTP 429 (Too Many Requests), while the managed
  # DRS rules return HTTP 403 (Forbidden) — the App Gateway WAF default. The
  # gateway's existing 403 custom error page applies to the managed-rule blocks.

  # Managed rule set. Microsoft_DefaultRuleSet (DRS) 2.2 is preferred over OWASP
  # CRS 3.2 here: it runs the modern WAF engine that rate limiting requires, is
  # tuned by Microsoft to produce fewer false positives on real traffic, and —
  # unlike CRS 3.2 — supports per-rule `action` and `sensitivity` for tightening
  # later. Active (blocking) while mode = Prevention.
  #
  # Tightening / loosening knobs (lenient now, tighten later):
  #   * Loosen: lower a noisy rule's sensitivity, or set its action to "Log"
  #     (inspect + log, don't block) via a rule_group_override block.
  #   * Suppress a known false positive: add an `exclusion` block (by header /
  #     cookie / query-arg name) under managed_rule_set or rule_group_override.
  #   * Full stop: set waf_mode = "Detection" to make ALL rules non-blocking
  #     (rate limiting included) while you tune.
  # Watch ApplicationGatewayFirewallLog for matched rule IDs before tightening.
  managed_rules {
    managed_rule_set {
      type    = "Microsoft_DefaultRuleSet"
      version = "2.2"
    }
  }

  tags = {
    environment = "shared"
  }
}
