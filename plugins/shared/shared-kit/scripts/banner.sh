#!/bin/sh
# Print a boxed ASCII banner around the given text (default HELLO).
text=${1:-HELLO}
text=$(printf '%s' "$text" | tr '[:lower:]' '[:upper:]')
len=${#text}
width=$((len + 4))
line=$(printf '%*s' "$width" '' | tr ' ' '#')
printf '%s\n' "$line"
printf '# %s #\n' "$text"
printf '%s\n' "$line"
printf '%s\n' "🏓 pong from shared-kit script v1.0.0"
