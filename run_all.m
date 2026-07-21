%RUN_ALL 主入口：运行全部实验并导出 300 dpi 图片。

clear; clc; close all;

project_dir = fileparts(mfilename('fullpath'));
function_dir = fullfile(project_dir, 'func');
output_dir = fullfile(project_dir, 'figs');
addpath(function_dir);

config = mu_kim_config();
results = run_mu_kim_experiments(config);

print_mu_kim_results(results, 'all');
plot_mu_kim_results(results, output_dir, 'all');

fprintf('\n复现完成，图片保存在：\n  %s\n', output_dir);
