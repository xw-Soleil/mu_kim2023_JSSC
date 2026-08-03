%BENCHMARKING_QUANT 展示 residue 量化造成的 MAE 误差平台。

clear; clc; close all;

project_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(project_dir, 'func'));

results = run_mu_kim_experiments(mu_kim_config());
print_mu_kim_results(results, 'quantization');
plot_mu_kim_results(results, fullfile(project_dir, 'figs'), 'quantization');
