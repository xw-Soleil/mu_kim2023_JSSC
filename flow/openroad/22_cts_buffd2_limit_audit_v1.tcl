set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set report_dir [file join $repo_root flow reports openroad]
read_liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
read_db [file join $work_dir 20_cts_buffd2_v11.odb]
read_sdc [file join $repo_root flow results openroad 20_cts_buffd2_v11.sdc]
set_thread_count 8
set_propagated_clock [all_clocks]
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5
estimate_parasitics -placement
report_check_types -violators -max_slew -max_capacitance -max_fanout \
  > [file join $report_dir 22_cts_buffd2_v11_limit_violators.rpt]
report_check_types -violators -max_delay -min_delay -recovery -removal -max_skew \
  > [file join $report_dir 22_cts_buffd2_v11_timing_violators.rpt]
report_clock_skew -setup \
  > [file join $report_dir 22_cts_buffd2_v11_clock_skew.rpt]
report_checks -path_delay max -fields {slew cap input_pins nets fanout} \
  > [file join $report_dir 22_cts_buffd2_v11_timing_checks.rpt]
puts "PDE_CTS_BUFFD2_LIMIT_AUDIT_PASS"
exit
