#!/bin/bash
# SCL's optional libudev inventory path crashes during license checkout on this host.
# Put an invalid libudev.so.1 first in the search path so dlopen() fails and SCL uses
# its non-udev fallback. This affects only the wrapped process and its children.
set -eu

if [ "$#" -eq 0 ]; then
  echo "usage: $0 command [args ...]" >&2
  exit 2
fi

# Diagnostic escape hatch. The system libudev path is known to be unstable here.
if [ "${PDE_SNPS_USE_SYSTEM_UDEV:-0}" = 1 ]; then
  exec "$@"
fi

MASK_DIR=${PDE_SNPS_UDEV_MASK_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pde-snps/no-udev}
MASK_LIB=$MASK_DIR/libudev.so.1

mkdir -p "$MASK_DIR"
chmod 700 "$MASK_DIR"

if [ -L "$MASK_LIB" ]; then
  if [ "$(readlink "$MASK_LIB")" != /dev/null ]; then
    echo "unexpected libudev mask target: $MASK_LIB -> $(readlink "$MASK_LIB")" >&2
    exit 1
  fi
elif [ -e "$MASK_LIB" ]; then
  echo "refusing to replace existing libudev mask: $MASK_LIB" >&2
  exit 1
else
  ln -s /dev/null "$MASK_LIB"
fi

export LD_LIBRARY_PATH="$MASK_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$@"
