#!/bin/bash

REPO="AlexTkDev/MacOSCleaner"

DATA=$(curl -s "https://api.github.com/repos/$REPO/releases?per_page=100")

echo "MacOSCleaner Downloads"
echo "======================"
echo

echo "$DATA" | jq -r '
    .[] |
    "\(.tag_name): \([.assets[].download_count] | add // 0)"
'

echo
echo "Total downloads: $(echo "$DATA" | jq '[.[].assets[].download_count // 0] | add')"