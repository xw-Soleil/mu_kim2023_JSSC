function output_files = plot_mu_kim_results(results, output_dir, selection)
%PLOT_MU_KIM_RESULTS 统一生成并导出复现图片。
% selection 可选择 convergence、cost、equivalence、residue、
% quantization、dsm、summary 或 all。

if nargin < 2 || isempty(output_dir)
    output_dir = fullfile(pwd, 'figs');
end
if nargin < 3 || isempty(selection)
    selection = {'all'};
elseif ischar(selection) || isstring(selection)
    selection = cellstr(selection);
end
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

if any(strcmp(selection, 'all'))
    selection = {'convergence', 'cost', 'equivalence', 'residue', 'dsm', 'summary'};
end

output_files = {};
for item_id = 1:numel(selection)
    item = lower(selection{item_id});
    switch item
        case 'convergence'
            fig = new_figure([1100, 680]);
            draw_convergence(axes(fig), results, false);
            output_files{end + 1} = save_figure(fig, output_dir, ...
                'fig1_methods_mae.png'); %#ok<AGROW>

        case 'cost'
            fig = new_figure([1250, 620]);
            layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
            draw_cost(nexttile(layout), results, 'work', false);
            draw_cost(nexttile(layout), results, 'latency', false);
            output_files{end + 1} = save_figure(fig, output_dir, ...
                'fig2_energy_latency.png'); %#ok<AGROW>

        case 'equivalence'
            fig = new_figure([1250, 620]);
            layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
            draw_equivalence(nexttile(layout), results, false);
            draw_solution_difference(nexttile(layout), results, false);
            output_files{end + 1} = save_figure(fig, output_dir, ...
                'fig3_residue_equiv.png'); %#ok<AGROW>

        case 'residue'
            fig = new_figure([1100, 680]);
            draw_residue_decay(axes(fig), results, false);
            output_files{end + 1} = save_figure(fig, output_dir, ...
                'fig4_residue_decay.png'); %#ok<AGROW>

        case 'quantization'
            fig = new_figure([1100, 680]);
            draw_quantization_only(axes(fig), results, false);
            output_files{end + 1} = save_figure(fig, output_dir, ...
                'fig5a_quantization_only.png'); %#ok<AGROW>

        case 'dsm'
            fig = new_figure([1350, 650]);
            layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
            draw_dsm_curves(nexttile(layout), results, false);
            draw_dsm_final(nexttile(layout), results, false);
            output_files{end + 1} = save_figure(fig, output_dir, ...
                'fig5_quant_dsm.png'); %#ok<AGROW>

        case 'summary'
            fig = new_figure([1800, 1050]);
            layout = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
            draw_convergence(nexttile(layout), results, true);
            draw_cost(nexttile(layout), results, 'work', true);
            draw_cost(nexttile(layout), results, 'latency', true);
            draw_equivalence(nexttile(layout), results, true);
            draw_residue_decay(nexttile(layout), results, true);
            draw_dsm_curves(nexttile(layout), results, true);
            sgtitle(layout, 'Mu & Kim (JSSC 2023): algorithm-level reproduction', ...
                'FontName', 'Helvetica', 'FontSize', 18, 'FontWeight', 'bold');
            output_files{end + 1} = save_figure(fig, output_dir, ...
                'summary_onepage.png'); %#ok<AGROW>

        otherwise
            error('未知的绘图选项：%s', item);
    end
end
end

function fig = new_figure(size_px)
fig = figure('Color', 'white', 'Position', [80, 80, size_px]);
end

function filename = save_figure(fig, output_dir, basename)
filename = fullfile(output_dir, basename);
drawnow;
exportgraphics(fig, filename, 'Resolution', 300, 'BackgroundColor', 'white');
fprintf('已保存：%s\n', filename);
end

function draw_convergence(ax, results, compact)
colors = method_colors();
styles = {'-', '--', '-.', '-'};
hold(ax, 'on');
for method_id = 1:numel(results.method_names)
    y = [1, results.mae{method_id}];
    plot(ax, 0:(numel(y) - 1), y, ...
        'Color', colors(method_id, :), 'LineStyle', styles{method_id}, ...
        'LineWidth', 2.2);
    plot(ax, numel(y) - 1, y(end), 'o', ...
        'Color', colors(method_id, :), 'MarkerFaceColor', 'white', ...
        'MarkerSize', 6, 'LineWidth', 1.2, 'HandleVisibility', 'off');
end
yline(ax, results.config.convergence.mae_target, ':', 'MAE target', ...
    'Color', [0.35, 0.35, 0.35], 'LabelHorizontalAlignment', 'right', ...
    'LabelVerticalAlignment', 'bottom', ...
    'HandleVisibility', 'off');
set(ax, 'YScale', 'log');
xlabel(ax, 'Grid updates');
ylabel(ax, 'Mean absolute error (MAE)');
if compact
    title(ax, '(a) Convergence');
    legend(ax, results.method_names, 'Location', 'southwest', 'FontSize', 8);
else
    title(ax, {'Convergence of four update schedules', ...
        sprintf('%dx%d grid, unit Dirichlet boundary, target MAE = 10^{-3}', ...
                results.config.convergence.grid_size, ...
                results.config.convergence.grid_size)});
    legend(ax, results.method_names, 'Location', 'southwest', 'NumColumns', 2);
end
ylim(ax, [8e-4, 1.2]);
style_axes(ax, true, compact);
end

function draw_cost(ax, results, kind, compact)
colors = method_colors();
switch kind
    case 'work'
        values = results.pe_updates;
        panel_title = 'Computational work';
        axis_label = 'PE updates';
        note = 'energy proxy';
        panel_letter = '(b)';
    case 'latency'
        values = results.cycle_proxy;
        panel_title = 'Minimum latency';
        axis_label = 'Algorithm-level cycles';
        note = 'maximum-parallelism proxy';
        panel_letter = '(c)';
end

b = barh(ax, values, 0.62, 'FaceColor', 'flat', ...
    'EdgeColor', [0.25, 0.25, 0.25], 'LineWidth', 0.7);
b.CData = colors;
set(ax, 'YTick', 1:numel(values), 'YTickLabel', results.method_names, ...
    'YDir', 'reverse');
xlim(ax, [0, max(values) * 1.23]);
tick_step = nice_tick_step(max(values) * 1.15, 5);
xticks(ax, 0:tick_step:(ceil(max(values) * 1.15 / tick_step) * tick_step));
for method_id = 1:numel(values)
    text(ax, values(method_id) + max(values) * 0.025, method_id, ...
        sprintf('%d', values(method_id)), 'VerticalAlignment', 'middle', ...
        'FontName', 'Helvetica', 'FontSize', 10, 'Color', [0.15, 0.15, 0.15]);
end
xlabel(ax, axis_label);
if compact
    title(ax, sprintf('%s %s (%s)', panel_letter, panel_title, note));
else
    title(ax, {panel_title, sprintf('Fig. 6 comparison; %s', note)});
end
style_axes(ax, false, compact);
% 横向网格会穿过柱形图，因此只保留较浅的纵向参考线。
set(ax, 'XGrid', 'on', 'YGrid', 'off', ...
    'XMinorGrid', 'off', 'YMinorGrid', 'off', ...
    'GridColor', [0.86, 0.87, 0.89], 'GridAlpha', 0.42);
end

function draw_equivalence(ax, results, compact)
jacobi_id = find(strcmp(results.method_names, 'Jacobi'), 1);
value_mae = results.mae{jacobi_id};
residue_mae = results.residue_mae{jacobi_id};

hold(ax, 'on');
plot(ax, 1:numel(value_mae), value_mae, '-', 'Color', [0.00, 0.45, 0.74], ...
    'LineWidth', 4.0);
plot(ax, 1:numel(residue_mae), residue_mae, '--', 'Color', [0.90, 0.35, 0.05], ...
    'LineWidth', 1.8);
set(ax, 'YScale', 'log');
xlabel(ax, 'Grid updates');
ylabel(ax, 'MAE');
if compact
    title(ax, '(d) Value/residue equivalence');
    legend(ax, {'Value form', 'Residue form'}, 'Location', 'southwest', 'FontSize', 8);
else
    title(ax, {'Equivalent bookkeeping', ...
        'Jacobi and residue-based Jacobi follow the same trajectory'});
    legend(ax, {'Value form', 'Residue form'}, 'Location', 'southwest');
end
style_axes(ax, true, compact);
end

function draw_solution_difference(ax, results, compact)
values = max(results.solution_difference, eps);
y = 1:numel(values);
hold(ax, 'on');
for method_id = 1:numel(values)
    semilogx(ax, values(method_id), y(method_id), 'o', ...
        'Color', method_colors(method_id), 'MarkerFaceColor', method_colors(method_id), ...
        'MarkerSize', 8, 'LineWidth', 1.2);
    text(ax, values(method_id) * 1.08, y(method_id), ...
        sprintf('%.1e', results.solution_difference(method_id)), ...
        'VerticalAlignment', 'middle', 'FontSize', 10);
end
set(ax, 'YTick', y, 'YTickLabel', results.method_names, 'YDir', 'reverse');
ylim(ax, [0.5, numel(values) + 0.5]);
xlabel(ax, 'max |u_{value} - u_{residue}|');
title(ax, 'Final numerical difference (floating point)');
set(ax, 'XScale', 'log');
xlim(ax, [4e-16, 1.6e-15]);
style_axes(ax, true, compact);
end

function draw_residue_decay(ax, results, compact)
colors = method_colors();
styles = {'-', '--', '-.', '-'};
hold(ax, 'on');
for method_id = 1:numel(results.method_names)
    y = results.max_residue{method_id};
    plot(ax, 1:numel(y), y, 'Color', colors(method_id, :), ...
        'LineStyle', styles{method_id}, 'LineWidth', 2.1);
end
set(ax, 'YScale', 'log');
xlabel(ax, 'Grid updates');
ylabel(ax, 'Maximum residue magnitude');
if compact
    title(ax, '(e) Residue decay');
    legend(ax, results.method_names, 'Location', 'southwest', 'FontSize', 8);
else
    title(ax, {'Residue magnitude decreases during iteration', ...
        'This trend motivates dynamic-precision bit-serial operation'});
    legend(ax, results.method_names, 'Location', 'southwest', 'NumColumns', 2);
end
style_axes(ax, true, compact);
end

function draw_quantization_only(ax, results, compact)
q = results.quantization;
colors = [0.15, 0.15, 0.15; 0.85, 0.20, 0.15; 0.05, 0.35, 0.75];
hold(ax, 'on');
plot(ax, 1:numel(q.float_mae), q.float_mae, ':', ...
    'Color', colors(1, :), 'LineWidth', 2.2);
for bit_id = 1:numel(q.bits)
    y = q.no_dsm_mae{bit_id};
    plot(ax, 1:numel(y), y, '-', 'Color', colors(bit_id + 1, :), 'LineWidth', 2.2);
end
set(ax, 'YScale', 'log');
xlabel(ax, 'Grid updates');
ylabel(ax, 'Mean absolute error (MAE)');
labels = [{'Floating point'}, arrayfun(@(b) sprintf('%d-bit', b), q.bits, 'UniformOutput', false)];
legend(ax, labels, 'Location', 'southwest');
title(ax, {'Quantization creates an MAE floor', ...
    sprintf('%dx%d residue-based checkerboard FDM', ...
            results.config.quantization.grid_size, ...
            results.config.quantization.grid_size)});
style_axes(ax, true, compact);
end

function draw_dsm_curves(ax, results, compact)
q = results.quantization;
bit_colors = [0.86, 0.20, 0.16; 0.08, 0.36, 0.76];
hold(ax, 'on');
plot(ax, 1:numel(q.float_mae), q.float_mae, ':', ...
    'Color', [0.20, 0.20, 0.20], 'LineWidth', 2.3);
labels = {'Floating point'};
for bit_id = 1:numel(q.bits)
    no_dsm = q.no_dsm_mae{bit_id};
    with_dsm = q.dsm_mae{bit_id};
    plot(ax, 1:numel(no_dsm), no_dsm, '-', ...
        'Color', bit_colors(bit_id, :), 'LineWidth', 2.2);
    plot(ax, 1:numel(with_dsm), with_dsm, '--', ...
        'Color', bit_colors(bit_id, :), 'LineWidth', 2.2);
    labels{end + 1} = sprintf('%d-bit', q.bits(bit_id)); %#ok<AGROW>
    labels{end + 1} = sprintf('%d-bit + DSM', q.bits(bit_id)); %#ok<AGROW>
end
set(ax, 'YScale', 'log');
xlabel(ax, 'Grid updates');
ylabel(ax, 'Mean absolute error (MAE)');
if compact
    title(ax, '(f) DSM error feedback');
    legend(ax, labels, 'Location', 'southwest', 'FontSize', 8);
else
    title(ax, {'DSM pushes the quantization floor downward', ...
        sprintf('%dx%d residue-based checkerboard FDM', ...
                results.config.quantization.grid_size, ...
                results.config.quantization.grid_size)});
    legend(ax, labels, 'Location', 'southwest');
end
style_axes(ax, true, compact);
end

function draw_dsm_final(ax, results, compact)
q = results.quantization;
values = [q.final_no_dsm(:), q.final_dsm(:)];
b = bar(ax, values, 'grouped', 'EdgeColor', [0.25, 0.25, 0.25], 'LineWidth', 0.7);
b(1).FaceColor = [0.72, 0.74, 0.77];
b(2).FaceColor = [0.10, 0.60, 0.52];
set(ax, 'YScale', 'log', 'XTickLabel', ...
    arrayfun(@(x) sprintf('%d-bit', x), q.bits, 'UniformOutput', false));
ylabel(ax, 'Final MAE after 640 updates');
title(ax, 'Final accuracy and DSM improvement');
ylim(ax, [1e-6, 3e-1]);
legend(ax, {'Without DSM', 'With DSM'}, 'Location', 'northeast');
for bit_id = 1:numel(q.bits)
    text(ax, b(2).XEndPoints(bit_id), q.final_dsm(bit_id) * 2.1, ...
        sprintf('%.0fx better', q.improvement(bit_id)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'Color', [0.04, 0.40, 0.34], 'FontWeight', 'bold', 'FontSize', 11);
end
style_axes(ax, true, compact);
end

function style_axes(ax, minor_grid, compact)
if compact
    font_size = 9;
else
    font_size = 11;
end
set(ax, 'FontName', 'Helvetica', 'FontSize', font_size, ...
    'LineWidth', 0.8, 'TickDir', 'out', 'Box', 'off', ...
    'XColor', [0.18, 0.18, 0.18], 'YColor', [0.18, 0.18, 0.18], ...
    'GridColor', [0.84, 0.86, 0.88], 'GridAlpha', 0.42, ...
    'MinorGridColor', [0.91, 0.92, 0.93], 'MinorGridAlpha', 0.28, ...
    'Layer', 'top');
if isprop(ax, 'Toolbar')
    ax.Toolbar.Visible = 'off';
end
grid(ax, 'on');
if minor_grid
    grid(ax, 'minor');
    set(ax, 'XMinorGrid', 'off', 'YMinorGrid', 'on');
end
end

function step = nice_tick_step(axis_max, target_intervals)
% 从 1/2/2.5/5 序列中选择易读的刻度间距。
raw_step = axis_max / target_intervals;
decade = 10^floor(log10(raw_step));
candidates = decade * [1, 2, 2.5, 5, 10];
[~, best] = min(abs(candidates - raw_step));
step = candidates(best);
end

function colors = method_colors(index)
colors = [0.00, 0.45, 0.74; ...  % Jacobi 方法
          0.90, 0.40, 0.05; ...  % Hybrid 方法
          0.47, 0.67, 0.19; ...  % Gauss-Seidel 方法
          0.49, 0.18, 0.56];     % Checkerboard 方法
if nargin > 0
    colors = colors(index, :);
end
end
