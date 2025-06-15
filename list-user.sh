#!/bin/bash
jq -r '.inbounds[].settings.clients[] | [.email, .id // .password, .expire] | @tsv' /usr/local/etc/xray/config.json
