%EXPLORE_SOR 扫描红黑 SOR 的松弛因子。
% 本实验只验证迭代轮数；RTL 仍需处理加权运算、保护位和 DSM 稳定性。

clear; clc; close all;
here = fileparts(mfilename('fullpath'));
addpath(here);
addpath(fullfile(here, '..', 'func'));

tol = 1e-3;
max_updates = 2000;
grid_sizes = [9, 20];

figure('Color', 'white', 'Position', [80, 80, 1250, 600]);
layout = tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

for grid_id = 1:numel(grid_sizes)
    N = grid_sizes(grid_id);
    omega = 1:0.025:1.95;
    updates = zeros(size(omega));
    for omega_id = 1:numel(omega)
        updates(omega_id) = solve_laplace( ...
            @(u) sor_checkerboard_step(u, omega(omega_id)), ...
            N, tol, max_updates);
    end

    omega_theory = 2 / (1 + sin(pi/(N+1)));
    checkerboard_updates = solve_laplace( ...
        @checkerboard_step, N, tol, max_updates);
    theory_updates = solve_laplace( ...
        @(u) sor_checkerboard_step(u, omega_theory), ...
        N, tol, max_updates);
    shift_friendly_updates = solve_laplace( ...
        @(u) sor_checkerboard_step(u, 1.75), ...
        N, tol, max_updates);

    fprintf(['N=%2d: checkerboard %3d | theory omega %.3f -> %3d (%.1fx) ' ...
             '| omega 1.75 -> %3d\n'], ...
        N, checkerboard_updates, omega_theory, theory_updates, ...
        checkerboard_updates/theory_updates, shift_friendly_updates);

    ax = nexttile(layout);
    plot(ax, omega, updates, 'Color', [0.00, 0.45, 0.74], 'LineWidth', 2.2);
    hold(ax, 'on');
    xline(ax, omega_theory, '--', sprintf('theory %.3f', omega_theory), ...
        'Color', [0.86, 0.20, 0.16], 'LabelOrientation', 'horizontal');
    yline(ax, checkerboard_updates, ':', ...
        sprintf('checkerboard %d', checkerboard_updates), ...
        'Color', [0.25, 0.25, 0.25]);
    plot(ax, omega_theory, theory_updates, 'o', 'MarkerSize', 7, ...
        'MarkerFaceColor', [0.86, 0.20, 0.16], 'MarkerEdgeColor', 'white');
    xlabel(ax, 'Relaxation factor \omega');
    ylabel(ax, 'Updates to reach MAE <= 10^{-3}');
    title(ax, sprintf('%dx%d grid', N, N));
    y_lower = max(0, min(updates) - 5);
    y_upper = max(max(updates), checkerboard_updates) * 1.08;
    ylim(ax, [y_lower, y_upper]);
    set(ax, 'FontName', 'Helvetica', 'FontSize', 11, 'LineWidth', 0.8, ...
        'TickDir', 'out', 'Box', 'off', 'GridColor', [0.84, 0.86, 0.88], ...
        'GridAlpha', 0.65, 'Layer', 'top');
    grid(ax, 'on');
end

sgtitle(layout, 'Red-black SOR: value-level iteration sweep', ...
    'FontName', 'Helvetica', 'FontSize', 16, 'FontWeight', 'bold');
exportgraphics(gcf, fullfile(here, 'figs', 'sor_sweep.png'), ...
    'Resolution', 300, 'BackgroundColor', 'white');
