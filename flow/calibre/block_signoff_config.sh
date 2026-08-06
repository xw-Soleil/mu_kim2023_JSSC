#!/usr/bin/env bash
# Local configuration template for the TSMC65LP SP6M4x1z block-level
# Calibre DRC and antenna runs.  Every value can be overridden in the
# environment before this file is sourced.

: "${PDE_REPO_ROOT:=/home/sxw/PDE/pdeMujunjie}"
: "${PDE_CALIBRE_HOME:=/ssd0/mentor/Calibre2023/aoj_cal_2023.2_16.9}"
: "${PDE_LICENSE_FILE:=/ssd0/mentor/license/license.dat}"

: "${PDE_TOP:=pde_chip_top_safe}"
# 2026-08-06: default retargeted from the removed OpenROAD path to the
# full_clean_20260804 ICC2 deliverable (1 nm/dbu rescaled copy; the raw
# 0.1 nm ICC2 stream-out is pde_chip_top_safe.gds in the same directory).
: "${PDE_GDS:=/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.clean_20260804.dbu1000.gds}"

# The extracted /tmp tree is intentionally not used as the canonical input.
# These two members are reconstructed from the persistent local PDK archive.
: "${PDE_DRC_ARCHIVE:=/ssd0/PDKs/TSMC65nm/STDCELL/DRC_Calibre_65nm_v2.3a.tar.gz}"
: "${PDE_DRC_ARCHIVE_MEMBER:=MAIN_DRC_TopMz/CLN65S_6M_4X1Z.23a}"
: "${PDE_ANT_ARCHIVE_MEMBER:=ANTENNA_DRC/CN65S_6M.ANT.23a}"
: "${PDE_DRC_SOURCE_SHA256:=a763c116f8e76d69cdaca62d16ba21fd5a36f4c00ae27ecbc656886f1ec2f236}"
: "${PDE_ANT_SOURCE_SHA256:=70d8e89e33e1b3c162483e7c8f00fcd10f28031f431ea9094a1b67acdcc31974}"

: "${PDE_CALIBRE_WORK_ROOT:=${PDE_REPO_ROOT}/flow/work/calibre/block_signoff}"
: "${PDE_CALIBRE_RESULT_ROOT:=${PDE_REPO_ROOT}/flow/results/calibre}"
: "${PDE_CALIBRE_REPORT_ROOT:=${PDE_REPO_ROOT}/flow/reports/calibre}"

: "${PDE_DRC_DECK:=${PDE_CALIBRE_WORK_ROOT}/generated/CLN65S_6M_4X1Z.block_lp.23a}"
: "${PDE_ANT_DECK:=${PDE_CALIBRE_WORK_ROOT}/generated/CN65S_6M.block.ANT.23a}"
: "${PDE_DECK_MANIFEST:=${PDE_CALIBRE_WORK_ROOT}/generated/block_signoff_manifest.txt}"

: "${PDE_DRC_RDB:=${PDE_CALIBRE_RESULT_ROOT}/${PDE_TOP}_block_drc.db}"
: "${PDE_DRC_SUMMARY:=${PDE_CALIBRE_REPORT_ROOT}/${PDE_TOP}_block_drc.summary}"
: "${PDE_DRC_LOG:=${PDE_CALIBRE_REPORT_ROOT}/${PDE_TOP}_block_drc.log}"

: "${PDE_ANT_RDB:=${PDE_CALIBRE_RESULT_ROOT}/${PDE_TOP}_block_antenna.db}"
: "${PDE_ANT_SUMMARY:=${PDE_CALIBRE_REPORT_ROOT}/${PDE_TOP}_block_antenna.summary}"
: "${PDE_ANT_LOG:=${PDE_CALIBRE_REPORT_ROOT}/${PDE_TOP}_block_antenna.log}"

: "${PDE_CALIBRE_TURBO:=4}"
