%BENCHMARKING 比较四种网格更新方法的收敛过程。

clear; clc; close all;

project_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(project_dir, 'func'));

results = run_mu_kim_experiments(mu_kim_config());
print_mu_kim_results(results, 'methods');
plot_mu_kim_results(results, fullfile(project_dir, 'figs'), 'convergence');
