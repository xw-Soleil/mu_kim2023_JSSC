%BENCHMARKING_FIG6 复现 Fig. 6 的算法级开销对比。
% PE 更新数和周期数均为代理量，不是芯片实测结果。

clear; clc; close all;

project_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(project_dir, 'func'));

results = run_mu_kim_experiments(mu_kim_config());
print_mu_kim_results(results, 'methods');
plot_mu_kim_results(results, fullfile(project_dir, 'figs'), 'cost');
