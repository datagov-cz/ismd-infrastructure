# Realm user profile (Keycloak 24 declarative user profile).
#
# Why it is managed: Keycloak's default profile requires email for every user, and
# neither CAAIS nor NIA supplies one. With email required, the first-broker-login
# "Review Profile" step (update.profile.on.first.login = missing) and the
# VERIFY_PROFILE required action stop every new federated user on an
# "Update Account Information" page. Nothing downstream uses email — the backend
# keys users on preferred_username / sub — so email is optional here.
#
# First and last name (user_profile_names_required) are the display name only —
# users are identified by username (derived from NIA's PersonIdentifier / CAAIS's
# subject). When required, a citizen who switches names off at NIA's consent screen
# is asked for them once; the NIA mappers only overwrite them when NIA sends a value.
#
# This resource owns the WHOLE profile: every attribute below restates the Keycloak
# 24 defaults as read from the live test realm on 2026-09-17, except email.required.
# An attribute left out here would be removed from the realm.

resource "keycloak_realm_user_profile" "this" {
  count = var.manage_user_profile ? 1 : 0

  realm_id = keycloak_realm.ismd.id

  attribute {
    name         = "username"
    display_name = "$${username}"

    validator {
      name   = "length"
      config = { min = "3", max = "255" }
    }
    validator {
      name = "username-prohibited-characters"
    }
    validator {
      name = "up-username-not-idn-homograph"
    }

    # Read-only for users: federated usernames are derived from the IdP subject
    # (NIA: cz-cz-<PersonIdentifier>), the backend keys users on them, and the
    # first-login profile form must not let anyone rename themselves.
    permissions {
      view = ["admin", "user"]
      edit = ["admin"]
    }
  }

  attribute {
    name               = "email"
    display_name       = "$${email}"
    required_for_roles = var.user_profile_email_required ? ["user"] : []

    validator {
      name = "email"
    }
    validator {
      name   = "length"
      config = { max = "255" }
    }

    permissions {
      view = ["admin", "user"]
      edit = ["admin", "user"]
    }
  }

  attribute {
    name               = "firstName"
    display_name       = "$${firstName}"
    required_for_roles = var.user_profile_names_required ? ["user"] : []

    validator {
      name   = "length"
      config = { max = "255" }
    }
    validator {
      name = "person-name-prohibited-characters"
    }

    permissions {
      view = ["admin", "user"]
      edit = ["admin", "user"]
    }
  }

  attribute {
    name               = "lastName"
    display_name       = "$${lastName}"
    required_for_roles = var.user_profile_names_required ? ["user"] : []

    validator {
      name   = "length"
      config = { max = "255" }
    }
    validator {
      name = "person-name-prohibited-characters"
    }

    permissions {
      view = ["admin", "user"]
      edit = ["admin", "user"]
    }
  }

  group {
    name                = "user-metadata"
    display_header      = "User metadata"
    display_description = "Attributes, which refer to user metadata"
  }
}
