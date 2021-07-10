#!/usr/bin/env bash
# Decode base64 "value" attributes
jq '[ .[] | .value = (.value | @base64d) ]'