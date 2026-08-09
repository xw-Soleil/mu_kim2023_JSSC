clear; clc; close all;

%% 仿真参数
cfg.n_rows = 8;
cfg.n_cols = 8;
cfg.max_updates = 256;
cfg.residue_threshold = int32(0);

% 初始化矩阵
grid_r = zeros(cfg.n_rows + 2, cfg.n_cols + 2, 'int16');
grid_r (1,2:end-1) = int16(200);


%% 初始化ref参考模型（CheckBoard）和红黑折叠PE模型
ref.r = grid_r;
ref.u = zeros(size(grid_r), 'int16');


folded = init_folded_state(cfg.n_rows, cfg.n_cols, grid_r);
folded_DSM = init_folded_state(cfg.n_rows, cfg.n_cols, grid_r);

logical_points = cfg.n_rows * cfg.n_cols;
physical_points = cfg.n_rows * folded.n_pairs;
slot_utilization = logical_points / (2 * physical_points);


fprintf('网格内部点：%d x %d，共 %d 点\n', ...
    cfg.n_rows, cfg.n_cols, logical_points);
fprintf('折叠阵列：%d 个物理 PE，每个 PE 保存 red/black 两套状态\n', ...
    physical_points);

%% 逐轮运行，并与未折叠参考模型进行位精确比较

% 存储最大残差数组
max_residue_trace = zeros(cfg.max_updates, 1, 'int32');


triggered = false;


for update = 1:cfg.max_updates
    ref = checkerboard_int16_step(ref);
    folded = folded_pe_step(folded);
    folded_DSM = folded_DSM_pe_step(folded_DSM);

    [u_folded, r_folded] = unpack_folded_state(folded);
    [u_folded_DSM, r_folded_DSM] = unpack_folded_state(folded_DSM);
    u_ref = ref.u(2:end-1, 2:end-1);
    r_ref = ref.r(2:end-1, 2:end-1);

    assert(isequal(u_folded, u_ref), ...
        '第 %d 轮：折叠模型与参考模型的 solution 不一致。', update);
    assert(isequal(r_folded, r_ref), ...
        '第 %d 轮：折叠模型与参考模型的 residue 不一致。', update);

    max_residue_trace(update) = max(abs(int32(r_folded(:))));
    if max_residue_trace(update) <= cfg.residue_threshold
        triggered = true;
        break;
    end
end


max_residue_trace = max_residue_trace(1:update);
[u_final, r_final] = unpack_folded_state(folded);


if triggered
    fprintf('动态 trigger 在第 %d 轮停止：max|residue| = %d\n', ...
        update, max_residue_trace(end));
else
    fprintf('达到最大轮数 %d：max|residue| = %d\n', ...
        update, max_residue_trace(end));
end
fprintf('折叠模型已连续 %d 轮通过位精确参考检查。\n', update);
fprintf('阵列完成了 %d 个颜色相位：red 和 black 各 %d 次。\n', ...
    2 * update, update);



%% 结果显示
figure('Color', 'w', 'Name', 'Red-black folded PE model');

subplot(1, 2, 1);
imagesc(double(u_final));
axis image;
colorbar;
xlabel('列');
ylabel('行');
title(sprintf('最终 solution（%d 轮）', update));

subplot(1, 2, 2);
stairs(1:update, double(max_residue_trace), 'LineWidth', 1.8);
xlabel('完整红黑更新轮数');
ylabel('max |residue|');
title('动态 trigger 监测量');
ax = gca;
ax.GridAlpha = 0.14;
grid on;

if triggered
    assert(max(abs(int32(r_final(:)))) <= cfg.residue_threshold, ...
        '停止标志与最终 residue 状态不一致。');
end





%% 函数



%% 初始化 红黑PE折叠矩阵
function state = init_folded_state(n_rows, n_cols, grid_r)
    % 将每行相邻的一个红点和一个黑点折叠到同一个物理 PE
    state.n_rows = n_rows;
    state.n_cols = n_cols;
    state.n_pairs = ceil(n_cols / 2);  %向上取整
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


    % DSM参数存储
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




%%  对折叠PE进行操作+DSM
function next = folded_DSM_pe_step(state)
% 每个物理 PE 的 red/black 寄存器分时复用同一个平均值 ALU。

    next = state;
    next.r_red(:) = 0;
    next.r_black(:) = 0;

    % Red 相位：所有物理 PE 并行更新各自的 red 寄存器。
    for row = 1:state.n_rows
        for pair = 1:state.n_pairs
            if state.valid_red(row, pair)
                col = double(state.red_col(row, pair));
                [r_n, r_s, r_e, r_w] = read_four_neighbors(state, row, col);
                [next.r_red(row, pair), next.e_red(row, pair)] = shared_average_dsm_alu(r_n, r_s, r_e, r_w, state.e_red(row,pair));
            end
        end
    end

    % Black 相位：同一个 ALU 改读新 red residue，并写 black 寄存器。
    for row = 1:state.n_rows
        for pair = 1:state.n_pairs
            if state.valid_black(row, pair)
                col = double(state.black_col(row, pair));
                [r_n, r_s, r_e, r_w] = read_four_neighbors(next, row, col);
                [next.r_black(row, pair), next.e_black(row, pair)] = shared_average_dsm_alu(r_n, r_s, r_e, r_w, next.e_black(row,pair));
            end
        end
    end

    next.u_red = wrap_int16(int32(state.u_red) + int32(next.r_red));
    next.u_black = wrap_int16(int32(state.u_black) + int32(next.r_black));

    % 边界只作为初始 residue 注入一次。
    next.grid_r(:) = 0;
end

%%  对折叠PE进行操作
function next = folded_pe_step(state)
% 每个物理 PE 的 red/black 寄存器分时复用同一个平均值 ALU。

    next = state;
    next.r_red(:) = 0;
    next.r_black(:) = 0;

    % Red 相位：所有物理 PE 并行更新各自的 red 寄存器。
    for row = 1:state.n_rows
        for pair = 1:state.n_pairs
            if state.valid_red(row, pair)
                col = double(state.red_col(row, pair));
                [r_n, r_s, r_e, r_w] = read_four_neighbors(state, row, col);
                next.r_red(row, pair) = shared_average_alu(r_n, r_s, r_e, r_w);
            end
        end
    end

    % Black 相位：同一个 ALU 改读新 red residue，并写 black 寄存器。
    for row = 1:state.n_rows
        for pair = 1:state.n_pairs
            if state.valid_black(row, pair)
                col = double(state.black_col(row, pair));
                [r_n, r_s, r_e, r_w] = read_four_neighbors(next, row, col);
                next.r_black(row, pair) = shared_average_alu(r_n, r_s, r_e, r_w);
            end
        end
    end

    next.u_red = wrap_int16(int32(state.u_red) + int32(next.r_red));
    next.u_black = wrap_int16(int32(state.u_black) + int32(next.r_black));

    % 边界只作为初始 residue 注入一次。
    next.grid_r(:) = 0;
end




function [r_n, r_s, r_e, r_w] = read_four_neighbors(state, row, col)
% 从折叠寄存器或边界寄存器中读取四邻居 residue。

    r_n = read_folded_residue(state, row - 1, col);
    r_s = read_folded_residue(state, row + 1, col);
    r_e = read_folded_residue(state, row, col + 1);
    r_w = read_folded_residue(state, row, col - 1);
end


function value = read_folded_residue(state, row, col)
% 逻辑坐标自动映射到对应物理 PE 的 red/black 寄存器。

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
% 将折叠状态还原成普通二维网格，便于观察和验证。

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



%% 未折叠的二维参考CheckBoard模型
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


function [r_new, dsm_new] = shared_average_dsm_alu(r_n, r_s, r_e, r_w, e_prev)
    sum18 = int32(r_n) + int32(r_s) + int32(r_e) + int32(r_w) + int32(e_prev);
    avg   = idivide(sum18, int32(4), 'floor');
    r_new = int16(avg);

    % 取 sum18 的最低两位
    low2  = bitand(sum18, int32(3));   % 结果范围 0~3，类型仍为 int32

    dsm_new = int16(low2);  % 按需要转换输出类型
end


function r_new = shared_average_alu(r_n, r_s, r_e, r_w)
% 一个 PE 内的 red/black 两套寄存器共用这条运算路径。

    sum18 = int32(r_n) + int32(r_s) + int32(r_e) + int32(r_w);
    avg = idivide(sum18, int32(4), 'floor');
    r_new = int16(avg);
end


function y = wrap_int16(x)
% 模拟 RTL 写回 signed [15:0] 时的二进制回绕。

    x = int64(x);
    x = mod(x + int64(32768), int64(65536)) - int64(32768);
    y = int16(x);
end