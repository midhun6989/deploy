#!/bin/bash
# Replaces the custom init.sh script in the ARM template with the
# gzipped bas64 encoded changes from the local file

# Ensure you're at git root for relative pathing
cd $(git rev-parse --show-toplevel)

initScript='./bootstrap.sh'
armTemplate='../marketplace/mainTemplate.json'
jqFilter='.resources[] | select(.name | contains("init.sh")) | .properties.protectedSettings.script'

echo "Old script value" 
cat $armTemplate | jq "$jqFilter"

# Update the value in the JSON file by using the full JSON path to the key
encodedInit=$(cat $initScript | gzip -9 | base64)
jq "setpath(path($jqFilter); \"$encodedInit\")" $armTemplate > $armTemplate.tmp
mv $armTemplate.tmp $armTemplate 

echo "New script value"
cat $armTemplate | jq "$jqFilter"