#!/bin/sh
# Roll two six-sided dice and print the total.
set -- $(awk 'BEGIN{srand();print int(rand()*6)+1, int(rand()*6)+1}')
a=$1
b=$2
total=$((a + b))
printf '🎲 rolled %s + %s = %s\n' "$a" "$b" "$total"
printf '%s\n' "🏓 pong from shared-kit script v1.0.0"
