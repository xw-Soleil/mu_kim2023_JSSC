clear; clc; close all;

%% 仿真参数
cfg.n_rows = 20;
cfg.n_cols = 20;
cfg.max_updates = 640;
cfg.residue_threshold = int32(0);
cfg.ideal_tol = 1e-12;
cfg.ideal_max_updates = 20000;

% 动态位宽控制
cfg.dynamic_widths = [16, 12, 8, 4];
cfg.dynamic_thresholds = int32([32767, 2047, 127, 7]);

%% 缩放系数
FRAC_BITS = 7;
SCALE = int32(2^FRAC_BITS);   % = 128

% 初始化矩阵
grid_r = zeros(cfg.n_rows + 2, cfg.n_cols + 2, 'int16');
grid_r(1, 2:end-1)   = int16(200);
grid_r(end, 2:end-1) = int16(0);
grid_r(2:end-1, 1)   = int16(0);
grid_r(2:end-1, end) = int16(0);

% 定点缩放后的边界网格
grid_scale_r = zeros(cfg.n_rows + 2, cfg.n_cols + 2, 'int16');
top_boundary_code = int32(200) * SCALE;
assert(top_boundary_code >= -32768 && top_boundary_code <= 32767, ...
    '边界条件缩放后超出 int16 范围。');
grid_scale_r(1, 2:end-1)   = int16(top_boundary_code);
grid_scale_r(end, 2:end-1) = int16(0);
grid_scale_r(2:end-1, 1)   = int16(0);
grid_scale_r(2:end-1, end) = int16(0);


%% 初始化参考模型和红黑折叠 PE 模型
ref.r = grid_scale_r;
ref.u = zeros(size(grid_scale_r), 'int16');

folded = init_folded_state(cfg.n_rows, cfg.n_cols, grid_scale_r);
folded_DSM = init_folded_state(cfg.n_rows, cfg.n_cols, grid_scale_r);
folded_dynamic = init_folded_state(cfg.n_rows, cfg.n_cols, grid_scale_r);

% FP32 residue-based 红黑模型
fp32.r = single(grid_r);
fp32.u = zeros(size(grid_r), 'single');

% double 高精度稳态解
[u_ideal, ideal_updates] = solve_ideal_solution( ...
    grid_r, cfg.ideal_tol, cfg.ideal_max_updates);

logical_points = cfg.n_rows * cfg.n_cols;
physical_points = cfg.n_rows * folded.n_pairs;
slot_utilization = logical_points / (2 * physical_points);

fprintf('网格内部点：%d x %d，共 %d 点\n', ...
    cfg.n_rows, cfg.n_cols, logical_points);
fprintf('折叠阵列：%d 个物理 PE，每个 PE 保存 red/black 两套状态\n', ...
    physical_points);
fprintf('状态槽利用率：%.1f%%\n', 100 * slot_utilization);
fprintf('double 高精度参考解在 %d 轮后收敛\n', ideal_updates);

%% 固定轮数比较加 DSM 和不加 DSM
max_r_no_dsm = zeros(cfg.max_updates, 1, 'int32');
max_r_dsm = zeros(cfg.max_updates, 1, 'int32');
max_r_dynamic = zeros(cfg.max_updates, 1, 'int32');
max_r_fp32 = zeros(cfg.max_updates, 1);
mae_no_dsm = zeros(cfg.max_updates, 1);
mae_dsm = zeros(cfg.max_updates, 1);
mae_dynamic = zeros(cfg.max_updates, 1);
mae_fp32 = zeros(cfg.max_updates, 1);
dynamic_width_trace = zeros(cfg.max_updates, 1, 'uint8');

for update = 1:cfg.max_updates
    ref = checkerboard_int16_step(ref);
    folded = folded_pe_step(folded);
    folded_DSM = folded_DSM_pe_step(folded_DSM);

    % 本轮开始前检测全阵列 residue，再选择最小安全位宽
    active_width = select_dynamic_width( ...
        folded_dynamic, cfg.dynamic_widths, cfg.dynamic_thresholds);
    dynamic_width_trace(update) = uint8(active_width);
    folded_dynamic = folded_DSM_pe_step(folded_dynamic, active_width);

    fp32 = checkerboard_fp32_step(fp32);

    [u_folded, r_folded] = unpack_folded_state(folded);
    [u_folded_DSM, r_folded_DSM] = unpack_folded_state(folded_DSM);
    [u_folded_dynamic, r_folded_dynamic] = ...
        unpack_folded_state(folded_dynamic);
    u_fp32 = fp32.u(2:end-1, 2:end-1);
    r_fp32 = fp32.r(2:end-1, 2:end-1);
    u_ref = ref.u(2:end-1, 2:end-1);
    r_ref = ref.r(2:end-1, 2:end-1);

    % 验证折叠映射没有改变无 DSM 的计算结果
    assert(isequal(u_folded, u_ref), ...
        '第 %d 轮：折叠模型与参考模型的 solution 不一致。', update);
    assert(isequal(r_folded, r_ref), ...
        '第 %d 轮：折叠模型与参考模型的 residue 不一致。', update);
    assert(isequal(u_folded_dynamic, u_folded_DSM), ...
        '第 %d 轮：动态位宽改变了 solution。', update);
    assert(isequal(r_folded_dynamic, r_folded_DSM), ...
        '第 %d 轮：动态位宽改变了 residue。', update);

    max_r_no_dsm(update) = max(abs(int32(r_folded(:))));
    max_r_dsm(update) = max(abs(int32(r_folded_DSM(:))));
    max_r_dynamic(update) = max(abs(int32(r_folded_dynamic(:))));
    max_r_fp32(update) = double(max(abs(r_fp32(:))));
    

    error_no_dsm = double(u_folded) / double(SCALE) - u_ideal;
    error_dsm    = double(u_folded_DSM) / double(SCALE) - u_ideal;
    error_dynamic = double(u_folded_dynamic) / double(SCALE) - u_ideal;
    % fp32 不涉及缩放，直接比较
    error_fp32   = double(u_fp32) - u_ideal;
    mae_no_dsm(update) = mean(abs(error_no_dsm(:)));
    mae_dsm(update) = mean(abs(error_dsm(:)));
    mae_dynamic(update) = mean(abs(error_dynamic(:)));
    mae_fp32(update) = mean(abs(error_fp32(:)));
end

%% 最终结果
[u_final, r_final] = unpack_folded_state(folded);
[u_final_DSM, r_final_DSM] = unpack_folded_state(folded_DSM);
[u_final_dynamic, r_final_dynamic] = ...
    unpack_folded_state(folded_dynamic);
u_final_FP32 = fp32.u(2:end-1, 2:end-1);
r_final_FP32 = fp32.r(2:end-1, 2:end-1);

stop_no_dsm = find(max_r_no_dsm <= cfg.residue_threshold, 1, 'first');
stop_dsm = find(max_r_dsm <= cfg.residue_threshold, 1, 'first');
stop_dynamic = find(max_r_dynamic <= cfg.residue_threshold, 1, 'first');

final_mae_no_dsm = mae_no_dsm(end);
final_mae_dsm = mae_dsm(end);
final_mae_dynamic = mae_dynamic(end);
final_mae_fp32 = mae_fp32(end);
improvement = final_mae_no_dsm / final_mae_dsm;

if isempty(stop_dynamic)
    cycle_updates = cfg.max_updates;
else
    cycle_updates = stop_dynamic;
end

% 一个完整红黑更新包含两个相位，每相位为 B 个 CKA 加 1 个 CKB
fixed_16b_cycles = 2 * cycle_updates * (16 + 1);
dynamic_cycles = 2 * sum( ...
    double(dynamic_width_trace(1:cycle_updates)) + 1);
dynamic_speedup = fixed_16b_cycles / dynamic_cycles;

if isempty(stop_no_dsm)
    fprintf('不加 DSM：%d 轮内 residue 未归零\n', cfg.max_updates);
else
    fprintf('不加 DSM：第 %d 轮 residue 归零\n', stop_no_dsm);
end

if isempty(stop_dsm)
    fprintf('加入 DSM：%d 轮内 residue 未归零\n', cfg.max_updates);
else
    fprintf('加入 DSM：第 %d 轮 residue 归零\n', stop_dsm);
end

fprintf('不加 DSM 最终 MAE：%.6f\n', final_mae_no_dsm);
fprintf('加入 DSM 最终 MAE：%.6f\n', final_mae_dsm);
fprintf('动态位宽最终 MAE：%.6f\n', final_mae_dynamic);
fprintf('FP32 最终 MAE：%.6e\n', final_mae_fp32);
fprintf('DSM 改善倍数：%.3f 倍\n', improvement);
fprintf(['最终 max|residue|：不加 DSM = %d，加入 DSM = %d，' ...
         '动态位宽 = %d，FP32 = %.3e\n'], ...
    max(abs(int32(r_final(:)))), ...
    max(abs(int32(r_final_DSM(:)))), ...
    max(abs(int32(r_final_dynamic(:)))), ...
    double(max(abs(r_final_FP32(:)))));

fprintf('动态位宽切换：');
change_updates = [1; ...
    find(diff(double(dynamic_width_trace)) ~= 0) + 1];
for index = 1:numel(change_updates)
    change_update = change_updates(index);
    fprintf('第 %d 轮进入 %d-bit', ...
        change_update, dynamic_width_trace(change_update));
    if index < numel(change_updates)
        fprintf('，');
    else
        fprintf('\n');
    end
end
fprintf(['截至 residue 归零：固定 16-bit 为 %d 拍，' ...
         '动态位宽为 %d 拍，吞吐提升 %.3f 倍\n'], ...
    fixed_16b_cycles, dynamic_cycles, dynamic_speedup);

%% 图 1：MAE 曲线和最终 MAE
colors = [0.18, 0.48, 0.75; ...
          0.86, 0.33, 0.24; ...
          0.48, 0.28, 0.68; ...
          0.20, 0.62, 0.38];

fig_mae = figure('Color', 'w', 'Name', 'DSM MAE comparison', ...
    'Position', [100, 100, 1120, 440]);

subplot(1, 2, 1);
semilogy(1:cfg.max_updates, mae_no_dsm, ...
    'LineWidth', 1.8, 'Color', colors(1, :));
hold on;
semilogy(1:cfg.max_updates, mae_dsm, ...
    'LineWidth', 1.8, 'Color', colors(2, :));
semilogy(1:cfg.max_updates, mae_dynamic, ':', ...
    'LineWidth', 2.2, 'Color', colors(3, :));
semilogy(1:cfg.max_updates, mae_fp32, '--', ...
    'LineWidth', 1.8, 'Color', colors(4, :));
xlabel('红黑更新轮数');
ylabel('MAE');
title({'Folded Q8.7 与 FP32 仿真结果', ...
       '20×20 网格，边界条件：(200, 0, 0, 0)'});
legend('Folded Q8.7', 'Folded Q8.7 + DSM', ...
    'Folded Q8.7 动态位宽', 'FP32', ...
    'Location', 'northeast');
ax = gca;
ax.GridAlpha = 0.14;
ax.XGrid = 'off';
ax.YGrid = 'on';
ax.XMinorGrid = 'off';
ax.YMinorGrid = 'off';

subplot(1, 2, 2);
bar_values = [final_mae_no_dsm, final_mae_dsm, ...
              final_mae_dynamic, final_mae_fp32];
b = bar(bar_values, 0.62, 'FaceColor', 'flat');
b.CData = colors;
set(gca, 'XTick', 1:4, ...
    'XTickLabel', {'Q8.7', 'Q8.7+DSM', '动态', 'FP32'});
ylabel('最终 MAE');
title(sprintf('最终 MAE，DSM 改善 %.2f 倍', improvement));
for i = 1:4
    text(i, bar_values(i), sprintf('  %.4g', bar_values(i)), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom');
end
ax = gca;
ax.GridAlpha = 0.14;
ax.XGrid = 'off';
ax.YGrid = 'on';

%% 图 2：最终空间误差
final_error_no_dsm = ...
    double(u_final) / double(SCALE) - u_ideal;

final_error_dsm = ...
    double(u_final_DSM) / double(SCALE) - u_ideal;
final_error_dynamic = ...
    double(u_final_dynamic) / double(SCALE) - u_ideal;
final_error_fp32 = double(u_final_FP32) - u_ideal;
color_limit = max(abs([final_error_no_dsm(:); ...
                       final_error_dsm(:); ...
                       final_error_dynamic(:); ...
                       final_error_fp32(:)]));
if color_limit == 0
    color_limit = 1;
end

fig_error = figure('Color', 'w', 'Name', 'DSM spatial error', ...
    'Position', [140, 140, 1050, 760]);

subplot(2, 2, 1);
imagesc(final_error_no_dsm, [-color_limit, color_limit]);
axis image;
colorbar;
xlabel('列');
ylabel('行');
title(sprintf('不加 DSM，MAE = %.4f', final_mae_no_dsm));

subplot(2, 2, 2);
imagesc(final_error_dsm, [-color_limit, color_limit]);
axis image;
colorbar;
xlabel('列');
ylabel('行');
title(sprintf('加入 DSM，MAE = %.4f', final_mae_dsm));

subplot(2, 2, 3);
imagesc(final_error_dynamic, [-color_limit, color_limit]);
axis image;
colorbar;
xlabel('列');
ylabel('行');
title(sprintf('动态位宽，MAE = %.4f', final_mae_dynamic));

subplot(2, 2, 4);
imagesc(final_error_fp32, [-color_limit, color_limit]);
axis image;
colorbar;
xlabel('列');
ylabel('行');
title(sprintf('FP32，MAE = %.3e', final_mae_fp32));

colormap(fig_error, parula(256));
sgtitle('最终空间误差（统一色轴）');

%% 图 3：动态位宽触发与周期收益
trace_range = 1:cycle_updates;
fixed_cycle_trace = 2 * (16 + 1) * trace_range;
dynamic_cycle_trace = cumsum( ...
    2 * (double(dynamic_width_trace(trace_range)) + 1));

fig_dynamic = figure('Color', 'w', 'Name', 'Dynamic precision', ...
    'Position', [180, 180, 1350, 390]);

subplot(1, 3, 1);
semilogy(trace_range, ...
    max(double(max_r_dynamic(trace_range)), 0.5), ...
    'LineWidth', 1.8, 'Color', colors(1, :));
hold on;
yline(double(cfg.dynamic_thresholds(2)), '--', '12-bit 阈值');
yline(double(cfg.dynamic_thresholds(3)), '--', '8-bit 阈值');
yline(double(cfg.dynamic_thresholds(4)), '--', '4-bit 阈值');
xlabel('红黑更新轮数');
ylabel('max|residue|（定点编码值）');
title('全阵列阈值检测');
ax = gca;
ax.GridAlpha = 0.14;
ax.XGrid = 'off';
ax.YGrid = 'on';
ax.XMinorGrid = 'off';
ax.YMinorGrid = 'off';

subplot(1, 3, 2);
stairs(trace_range, double(dynamic_width_trace(trace_range)), ...
    'LineWidth', 2.0, 'Color', colors(3, :));
ylim([3, 17]);
yticks([4, 8, 12, 16]);
xlabel('红黑更新轮数');
ylabel('本轮计算位宽');
title('16→12→8→4 bit 调度');
ax = gca;
ax.GridAlpha = 0.14;
ax.XGrid = 'off';
ax.YGrid = 'on';

subplot(1, 3, 3);
plot(trace_range, fixed_cycle_trace, '--', ...
    'LineWidth', 1.8, 'Color', colors(1, :));
hold on;
plot(trace_range, dynamic_cycle_trace, ...
    'LineWidth', 2.0, 'Color', colors(3, :));
xlabel('完成的红黑更新轮数');
ylabel('累计时钟拍数');
title(sprintf('周期吞吐提升 %.2f 倍', dynamic_speedup));
legend('固定 16-bit', '动态位宽', 'Location', 'northwest');
ax = gca;
ax.GridAlpha = 0.14;
ax.XGrid = 'off';
ax.YGrid = 'on';


%% 初始化红黑 PE 折叠矩阵
function state = init_folded_state(n_rows, n_cols, grid_r)
% 将每行相邻的一个红点和一个黑点折叠到同一个物理 PE。

    state.n_rows = n_rows;
    state.n_cols = n_cols;
    state.n_pairs = ceil(n_cols / 2);
    state.grid_r = grid_r;

    pe_size = [n_rows, state.n_pairs];
    state.r_red = zeros(pe_size, 'int16');
    state.r_black = zeros(pe_size, 'int16');
    state.u_red = zeros(pe_size, 'int16');
    state.u_black = zeros(pe_size, 'int16');

    state.valid_red = false(pe_size);
    state.valid_black = false(pe_size);
    state.red_col = zeros(pe_size, 'uint16');
    state.black_col = zeros(pe_size, 'uint16');

    % DSM 误差状态，数值范围为 0~3
    state.e_red = zeros(pe_size, 'int16');
    state.e_black = zeros(pe_size, 'int16');

    for row = 1:n_rows
        for col = 1:n_cols
            pair = ceil(col / 2);
            if mod(row + col, 2) == 0
                state.valid_red(row, pair) = true;
                state.red_col(row, pair) = uint16(col);
            else
                state.valid_black(row, pair) = true;
                state.black_col(row, pair) = uint16(col);
            end
        end
    end
end


%% 对折叠 PE 进行操作，加 DSM
function next = folded_DSM_pe_step(state, active_width)
% Red/Black 两套寄存器分别保存自己的 DSM 误差。
    if nargin < 2
        active_width = 16;
    end

    next = state;
    next.r_red(:) = 0;
    next.r_black(:) = 0;

    % Red 相位
    for row = 1:state.n_rows
        for pair = 1:state.n_pairs
            if state.valid_red(row, pair)
                col = double(state.red_col(row, pair));
                [r_n, r_s, r_e, r_w] = read_four_neighbors(state, row, col);
                [next.r_red(row, pair), next.e_red(row, pair)] = ...
                    shared_average_dsm_alu( ...
                    r_n, r_s, r_e, r_w, state.e_red(row, pair),active_width);
            end
        end
    end

    % Black 相位
    for row = 1:state.n_rows
        for pair = 1:state.n_pairs
            if state.valid_black(row, pair)
                col = double(state.black_col(row, pair));
                [r_n, r_s, r_e, r_w] = read_four_neighbors(next, row, col);
                [next.r_black(row, pair), next.e_black(row, pair)] = ...
                    shared_average_dsm_alu( ...
                    r_n, r_s, r_e, r_w, state.e_black(row, pair),active_width);
            end
        end
    end

    next.u_red = wrap_int16(int32(state.u_red) + int32(next.r_red));
    next.u_black = wrap_int16(int32(state.u_black) + int32(next.r_black));

    % 边界只作为初始 residue 注入一次
    next.grid_r(:) = 0;
end


%% 对折叠 PE 进行操作，不加 DSM
function next = folded_pe_step(state, active_width)
% Red/Black 两套寄存器分时复用同一个平均值 ALU。

    if nargin < 2
        active_width = 16;
    end

    next = state;
    next.r_red(:) = 0;
    next.r_black(:) = 0;

    % Red 相位
    for row = 1:state.n_rows
        for pair = 1:state.n_pairs
            if state.valid_red(row, pair)
                col = double(state.red_col(row, pair));
                [r_n, r_s, r_e, r_w] = read_four_neighbors(state, row, col);
                next.r_red(row, pair) = ...
                    shared_average_alu( ...
                    r_n, r_s, r_e, r_w, active_width);
            end
        end
    end

    % Black 相位
    for row = 1:state.n_rows
        for pair = 1:state.n_pairs
            if state.valid_black(row, pair)
                col = double(state.black_col(row, pair));
                [r_n, r_s, r_e, r_w] = read_four_neighbors(next, row, col);
                next.r_black(row, pair) = ...
                    shared_average_alu( ...
                    r_n, r_s, r_e, r_w, active_width);
            end
        end
    end

    next.u_red = wrap_int16(int32(state.u_red) + int32(next.r_red));
    next.u_black = wrap_int16(int32(state.u_black) + int32(next.r_black));

    % 边界只作为初始 residue 注入一次
    next.grid_r(:) = 0;
end


function active_width = select_dynamic_width( ...
    state, widths, thresholds)
% 根据当前 residue 峰值选择最小安全位宽。

    residue_codes = [int32(state.r_red(:)); ...
                     int32(state.r_black(:)); ...
                     int32(state.grid_r(:))];
    max_abs_residue = max(abs(residue_codes));

    active_width = widths(1);
    for index = numel(widths):-1:1
        if max_abs_residue <= thresholds(index)
            active_width = widths(index);
            break;
        end
    end
end


function [r_n, r_s, r_e, r_w] = read_four_neighbors(state, row, col)
% 读取四邻居 residue。

    r_n = read_folded_residue(state, row - 1, col);
    r_s = read_folded_residue(state, row + 1, col);
    r_e = read_folded_residue(state, row, col + 1);
    r_w = read_folded_residue(state, row, col - 1);
end


function value = read_folded_residue(state, row, col)
% 将逻辑坐标映射到对应的 Red/Black 寄存器。

    if row < 1 || row > state.n_rows || col < 1 || col > state.n_cols
        value = state.grid_r(row + 1, col + 1);
        return;
    end

    pair = ceil(col / 2);
    if mod(row + col, 2) == 0
        assert(state.valid_red(row, pair) && ...
               double(state.red_col(row, pair)) == col, 'Red 映射错误。');
        value = state.r_red(row, pair);
    else
        assert(state.valid_black(row, pair) && ...
               double(state.black_col(row, pair)) == col, 'Black 映射错误。');
        value = state.r_black(row, pair);
    end
end


function [u, r] = unpack_folded_state(state)
% 将折叠状态还原成普通二维网格。

    u = zeros(state.n_rows, state.n_cols, 'int16');
    r = zeros(state.n_rows, state.n_cols, 'int16');

    for row = 1:state.n_rows
        for pair = 1:state.n_pairs
            if state.valid_red(row, pair)
                col = double(state.red_col(row, pair));
                u(row, col) = state.u_red(row, pair);
                r(row, col) = state.r_red(row, pair);
            end
            if state.valid_black(row, pair)
                col = double(state.black_col(row, pair));
                u(row, col) = state.u_black(row, pair);
                r(row, col) = state.r_black(row, pair);
            end
        end
    end
end


%% 未折叠的二维参考模型
function next = checkerboard_int16_step(state)

    u = state.u;
    r = state.r;
    r_next = zeros(size(r), 'int16');

    r_next([1 end], :) = r([1 end], :);
    r_next(:, [1 end]) = r(:, [1 end]);

    for i = 2:size(r, 1) - 1
        for j = 2:size(r, 2) - 1
            if mod(i + j, 2) == 0
                r_next(i, j) = shared_average_alu( ...
                    r(i - 1, j), r(i + 1, j), ...
                    r(i, j + 1), r(i, j - 1));
            end
        end
    end

    for i = 2:size(r, 1) - 1
        for j = 2:size(r, 2) - 1
            if mod(i + j, 2) == 1
                r_next(i, j) = shared_average_alu( ...
                    r_next(i - 1, j), r_next(i + 1, j), ...
                    r_next(i, j + 1), r_next(i, j - 1));
            end
        end
    end

    r_next([1 end], :) = 0;
    r_next(:, [1 end]) = 0;

    next.r = r_next;
    next.u = wrap_int16(int32(u) + int32(r_next));
end


%% FP32 residue-based 红黑模型
function next = checkerboard_fp32_step(state)

    u = state.u;
    r = state.r;
    r_next = zeros(size(r), 'single');

    r_next([1 end], :) = r([1 end], :);
    r_next(:, [1 end]) = r(:, [1 end]);

    for i = 2:size(r, 1) - 1
        for j = 2:size(r, 2) - 1
            if mod(i + j, 2) == 0
                sum_value = r(i - 1, j) + r(i + 1, j) + ...
                            r(i, j + 1) + r(i, j - 1);
                r_next(i, j) = sum_value / single(4);
            end
        end
    end

    for i = 2:size(r, 1) - 1
        for j = 2:size(r, 2) - 1
            if mod(i + j, 2) == 1
                sum_value = r_next(i - 1, j) + r_next(i + 1, j) + ...
                            r_next(i, j + 1) + r_next(i, j - 1);
                r_next(i, j) = sum_value / single(4);
            end
        end
    end

    r_next([1 end], :) = 0;
    r_next(:, [1 end]) = 0;

    next.r = r_next;
    next.u = u + r_next;
end


function [r_new, e_new] = shared_average_dsm_alu( ...
    r_n, r_s, r_e, r_w, e_prev, active_width)
% 保存本次除以 4 丢掉的误差，并反馈到下一轮。

    if nargin < 6
        active_width = 16;
        check_dynamic_range = false;
    else
        check_dynamic_range = true;
    end

    input_values = int32([r_n, r_s, r_e, r_w, e_prev]);
    lower_limit = -2^(active_width - 1);
    upper_limit = 2^(active_width - 1) - 1;

    if check_dynamic_range
        assert(all(input_values >= lower_limit & ...
                   input_values <= upper_limit), ...
            '%d-bit 模式下输入 residue/误差越界。', active_width);
    end

    sum18 = int32(r_n) + int32(r_s) + ...
            int32(r_e) + int32(r_w) + int32(e_prev);
    avg = idivide(sum18, int32(4), 'floor');
    r_new = wrap_signed_width(avg, active_width);

    error_value = sum18 - 4 * int32(r_new);
    assert(error_value >= 0 && error_value <= 3, ...
        'DSM 误差超出 0~3。');
    assert(sum18 == 4 * int32(r_new) + error_value, ...
        'DSM 误差反馈关系错误。');
    e_new = int16(error_value);
end


function r_new = shared_average_alu( ...
    r_n, r_s, r_e, r_w, active_width)
% 四邻居求和后算术右移 2 位。

    if nargin < 5
        active_width = 16;
        check_dynamic_range = false;
    else
        check_dynamic_range = true;
    end

    input_values = int32([r_n, r_s, r_e, r_w]);
    lower_limit = -2^(active_width - 1);
    upper_limit = 2^(active_width - 1) - 1;
    if check_dynamic_range
        assert(all(input_values >= lower_limit & ...
                   input_values <= upper_limit), ...
            '%d-bit 模式下输入 residue 越界。', active_width);
    end

    sum18 = int32(r_n) + int32(r_s) + int32(r_e) + int32(r_w);
    avg = idivide(sum18, int32(4), 'floor');
    r_new = wrap_signed_width(avg, active_width);
end


function [u_ideal, update] = solve_ideal_solution( ...
    grid_r, tol, max_updates)
% 使用 double 红黑迭代求高精度稳态解。

    u = double(grid_r);
    converged = false;

    for update = 1:max_updates
        u_old = u;

        for i = 2:size(u, 1) - 1
            for j = 2:size(u, 2) - 1
                if mod(i + j, 2) == 0
                    u(i, j) = (u(i - 1, j) + u(i + 1, j) + ...
                               u(i, j - 1) + u(i, j + 1)) / 4;
                end
            end
        end

        for i = 2:size(u, 1) - 1
            for j = 2:size(u, 2) - 1
                if mod(i + j, 2) == 1
                    u(i, j) = (u(i - 1, j) + u(i + 1, j) + ...
                               u(i, j - 1) + u(i, j + 1)) / 4;
                end
            end
        end

        if max(abs(u(:) - u_old(:))) <= tol
            converged = true;
            break;
        end
    end

    assert(converged, 'double 高精度参考解没有收敛。');
    u_ideal = u(2:end-1, 2:end-1);
end


function y = wrap_int16(x)
% 模拟 RTL 写回 signed 16-bit 时的回绕。

    x = int64(x);
    x = mod(x + int64(32768), int64(65536)) - int64(32768);
    y = int16(x);
end


function y = wrap_signed_width(x, width)
% 模拟 B-bit residue 写回后再符号扩展到 16 bit。

    modulus = bitshift(int64(1), width);
    half_range = bitshift(int64(1), width - 1);
    x = int64(x);
    x = mod(x + half_range, modulus) - half_range;
    y = int16(x);
end
