#!/bin/bash
cd lua/ccronexpr
gcc ccronexpr.c -I. -Wall -Wextra -std=c89 -o libccronexpr.so -fPIC -shared
