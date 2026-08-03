%BENCHMARKING_RESIDUE 验证值迭代与 residue 迭代的等价性。

clear; clc; close all;

project_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(project_dir, 'func'));

results = run_mu_kim_experiments(mu_kim_config());
print_mu_kim_results(results, 'residue');
plot_mu_kim_results(results, fullfile(project_dir, 'figs'), ...
    {'equivalence', 'residue'});
