%BENCHMARKING_DSM 比较加入和不加入 DSM 的量化 residue FDM。

clear; clc; close all;

project_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(project_dir, 'func'));

results = run_mu_kim_experiments(mu_kim_config());
print_mu_kim_results(results, 'dsm');
plot_mu_kim_results(results, fullfile(project_dir, 'figs'), 'dsm');
