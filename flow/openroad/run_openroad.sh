#!/bin/bash
# Launch the portable OpenROAD v2.0-17598 build on this CentOS 7 host.
#
# The binary is an Ubuntu 20.04 .deb build; it needs a newer glibc and several
# libraries CentOS 7 does not provide.  The whole runtime is self-contained
# under /home/sxw/local/openroad-runtime (copied out of /tmp on 2026-08-01
# after tmp cleanup deleted two libraries and broke the original setup):
#   openroad_2.0-17598_ubuntu20.04/  binary + or-tools + share/openroad tcl
#   ubuntu22_libc6/                  glibc 2.35 loader + libc (jammy)
#   ubuntu22_libgomp1/               libgomp (jammy)
#   tclreadline_2.3.8/               libtclreadline
#   ubuntu22_qt5charts/              libQt5Charts 5.12.8 (focal, xz deb)
#   ubuntu20_libpython38/            libpython3.8 (focal)
#   osscad-libs/                     Qt5/tcl/icu/X11 subset from oss-cad-suite
#                                    plus tcl8.6 init scripts
#
# Usage:  run_openroad.sh [openroad args...]
# e.g. :  run_openroad.sh -exit flow/openroad/10_place_v5.tcl

set -eu

rt=/home/sxw/local/openroad-runtime
or_root=$rt/openroad_2.0-17598_ubuntu20.04
loader=$rt/ubuntu22_libc6/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2

libpath=$rt/ubuntu22_libc6/lib/x86_64-linux-gnu
libpath=$libpath:$rt/ubuntu22_libgomp1/usr/lib/x86_64-linux-gnu
libpath=$libpath:$rt/tclreadline_2.3.8/usr/lib/x86_64-linux-gnu
libpath=$libpath:$or_root/opt/or-tools/lib
libpath=$libpath:$rt/ubuntu22_qt5charts/usr/lib/x86_64-linux-gnu
libpath=$libpath:$rt/ubuntu20_libpython38/usr/lib/x86_64-linux-gnu
libpath=$libpath:$rt/osscad-libs

for p in "$loader" "$or_root/usr/bin/openroad"; do
  if [[ ! -e $p ]]; then
    echo "run_openroad.sh: missing $p" >&2
    exit 1
  fi
done

export TCL_LIBRARY=$rt/osscad-libs/tcl8.6
exec "$loader" --library-path "$libpath" "$or_root/usr/bin/openroad" "$@"
