#!/usr/bin/env bash
# Base64 encode string "value" attributes
jq '[ .[] | .value = (.value | @base64) ]'