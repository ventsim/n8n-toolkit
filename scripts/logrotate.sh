#!/usr/bin/env bash
find logs -type f -size +10M -exec truncate -s 0 {} \;