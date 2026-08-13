# AI Apps Module
# Deploys the ISMD Semantic Modeling Assistant (ismd-ai) — a Spring Boot service
# that generates class/property/relationship suggestions via an LLM (OpenAI) and
# the public ESEL SPARQL endpoint.
#
# Topology: internal-only. Reached app-to-app over the Container App Environment
# internal network (consumed by the tool backend), like the validator backend.
# No public App Gateway route.
#
# State: stateless container. All persistence (feedback, jobs, token usage) lives
# in Postgres — a dedicated `ismd_ai` database created on the tool's existing
# Flexible Server (see database.tf), so there is no separate DB server to run.
#
# Files: variables.tf | app.tf (container app + secrets) | database.tf | outputs.tf
