#!/bin/bash
cd lua/ccronexpr
echo "epic man"
gcc ccronexpr.c -I. -Wall -Wextra -std=c89 -o libccronexpr.so -fPIC -shared
