# Add the waveform threshold metadata required by OpenSTA to the generated
# implementation-only Liberty.  This is a deterministic build step; the input
# remains the DC-extracted view and the output is the file consumed by P&R.

set repo_root /home/sxw/PDE/pdeMujunjie
set input_lib [file join $repo_root flow work openroad tcbn65lpwc_openroad_impl.lib]
set output_lib [file join $repo_root flow work openroad tcbn65lpwc_openroad_impl_sta.lib]

if {![file exists $input_lib]} {
  error "Missing generated implementation Liberty: $input_lib"
}

set input_fh [open $input_lib r]
set contents [read $input_fh]
close $input_fh

set marker {  nom_process : 1.0;}
set thresholds {  input_threshold_pct_rise : 50.0;
  input_threshold_pct_fall : 50.0;
  output_threshold_pct_rise : 50.0;
  output_threshold_pct_fall : 50.0;
  slew_lower_threshold_pct_rise : 20.0;
  slew_lower_threshold_pct_fall : 20.0;
  slew_upper_threshold_pct_rise : 80.0;
  slew_upper_threshold_pct_fall : 80.0;
  slew_derate_from_library : 1.0;
  nom_process : 1.0;}

if {[string first $marker $contents] < 0} {
  error "Could not locate Liberty insertion marker"
}
set finalized [string map [list $marker $thresholds] $contents]

set output_fh [open $output_lib w]
puts -nonewline $output_fh $finalized
close $output_fh

puts "PDE_OPENROAD_LIB_FINALIZED output=$output_lib"
