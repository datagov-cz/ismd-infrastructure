#!/usr/bin/env bash
while IFS='=' read -r name value; do
    name="${name//$'\r'/}"
    value="${value//$'\r'/}"
    if [ -n "$name" ] && [ -n "$value" ]; then
        export "$name=$value"
    fi
done < .env
