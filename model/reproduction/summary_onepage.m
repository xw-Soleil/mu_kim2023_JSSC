%SUMMARY_ONEPAGE 只生成六面板汇总图。

clear; clc; close all;

project_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(project_dir, 'func'));

results = run_mu_kim_experiments(mu_kim_config());
plot_mu_kim_results(results, fullfile(project_dir, 'figs'), 'summary');
