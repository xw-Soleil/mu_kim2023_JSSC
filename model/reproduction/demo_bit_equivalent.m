clear; clc; close all;
format long g;



%% Raw bit-vector 模型
% MATLAB 默认使用 double 保存数值，但所有硬件寄存器均保存原始比特编码：
%
%   unsigned W-bit : 0 ~ 2^W-1
%   signed   W-bit : 同样保存 0 ~ 2^W-1，
%                    仅在进入 signed ALU 时按二进制补码解释
%
% 例如 8'b11111011 在 MATLAB 中保存为 251；
% 进入 signed 8-bit ALU 时才解释为 -5。
%
% format short/long 只影响显示，不改变模型精度。

%% 硬件规格
hw.data_width = 16;
hw.frac_width = 7;
hw.dsm_width = 2;
hw.sum_guard_bits = 2;

hw.dynamic_widths = [16, 12, 8, 4];
hw.dynamic_thresholds = [32767, 2047, 127, 7];

%% 仿真参数
cfg.n_rows = 20;
cfg.n_cols = 20;
cfg.max_updates = 640;
cfg.ideal_tol = 1e-12;
cfg.ideal_max_updates = 20000;

validate_hw_spec(hw);
run_bit_vector_self_test();

%% 边界条件
boundary_physical = zeros(cfg.n_rows + 2, cfg.n_cols + 2);
boundary_physical(1, 2:end-1) = 200;

% physical -> Q8.7 signed value -> 16-bit two's-complement bits
boundary_bits = fx_encode_signed_bits( ...
    boundary_physical, hw.data_width, hw.frac_width, ...
    'boundary_bits');

assert(boundary_bits(1, 2) == 25600, ...
    '200 的 Q8.7 raw bits 应为 25600。');

%% 初始化硬件状态
fixed_no_dsm = init_folded_state( ...
    cfg.n_rows, cfg.n_cols, boundary_bits, hw);
fixed_dsm = init_folded_state( ...
    cfg.n_rows, cfg.n_cols, boundary_bits, hw);
dynamic_dsm = init_folded_state( ...
    cfg.n_rows, cfg.n_cols, boundary_bits, hw);

% FP64 只用于理想参考解，不属于硬件 bit-vector 路径
[u_ideal, ideal_updates] = solve_ideal_solution( ...
    boundary_physical, cfg.ideal_tol, cfg.ideal_max_updates);

%% 逐轮运行
max_r_no_dsm = zeros(cfg.max_updates, 1);
max_r_dsm = zeros(cfg.max_updates, 1);
max_r_dynamic = zeros(cfg.max_updates, 1);

mae_no_dsm = zeros(cfg.max_updates, 1);
mae_dsm = zeros(cfg.max_updates, 1);
mae_dynamic = zeros(cfg.max_updates, 1);

dynamic_width_trace = zeros(cfg.max_updates, 1);

for update = 1:cfg.max_updates
    fixed_no_dsm = folded_pe_step_bits( ...
        fixed_no_dsm, hw.data_width, false, hw);

    fixed_dsm = folded_pe_step_bits( ...
        fixed_dsm, hw.data_width, true, hw);

    active_width = select_dynamic_width( ...
        dynamic_dsm, hw.dynamic_widths, ...
        hw.dynamic_thresholds, hw);
    dynamic_width_trace(update) = active_width;

    dynamic_dsm = folded_pe_step_bits( ...
        dynamic_dsm, active_width, true, hw);

    [u_no_dsm_bits, r_no_dsm_bits] = ...
        unpack_folded_state(fixed_no_dsm);
    [u_dsm_bits, r_dsm_bits] = ...
        unpack_folded_state(fixed_dsm);
    [u_dynamic_bits, r_dynamic_bits] = ...
        unpack_folded_state(dynamic_dsm);

    % 每一轮结束后的寄存器 raw bits 必须完全一致
    assert(isequal(u_dynamic_bits, u_dsm_bits), ...
        '第 %d 轮：动态位宽改变了 DSM solution bits。', ...
        update);
    assert(isequal(r_dynamic_bits, r_dsm_bits), ...
        '第 %d 轮：动态位宽改变了 DSM residue bits。', ...
        update);

    r_no_dsm_value = hw_bits_to_signed( ...
        r_no_dsm_bits, hw.data_width, 'r_no_dsm_bits');
    r_dsm_value = hw_bits_to_signed( ...
        r_dsm_bits, hw.data_width, 'r_dsm_bits');
    r_dynamic_value = hw_bits_to_signed( ...
        r_dynamic_bits, hw.data_width, 'r_dynamic_bits');

    max_r_no_dsm(update) = max(abs(r_no_dsm_value(:)));
    max_r_dsm(update) = max(abs(r_dsm_value(:)));
    max_r_dynamic(update) = max(abs(r_dynamic_value(:)));

    u_no_dsm_physical = fx_decode_signed_bits( ...
        u_no_dsm_bits, hw.data_width, hw.frac_width);
    u_dsm_physical = fx_decode_signed_bits( ...
        u_dsm_bits, hw.data_width, hw.frac_width);
    u_dynamic_physical = fx_decode_signed_bits( ...
        u_dynamic_bits, hw.data_width, hw.frac_width);

    mae_no_dsm(update) = mean(abs( ...
        u_no_dsm_physical(:) - u_ideal(:)));
    mae_dsm(update) = mean(abs( ...
        u_dsm_physical(:) - u_ideal(:)));
    mae_dynamic(update) = mean(abs( ...
        u_dynamic_physical(:) - u_ideal(:)));
end

%% 最终结果
[u_final_no_dsm_bits, r_final_no_dsm_bits] = ...
    unpack_folded_state(fixed_no_dsm);
[u_final_dsm_bits, r_final_dsm_bits] = ...
    unpack_folded_state(fixed_dsm);
[u_final_dynamic_bits, r_final_dynamic_bits] = ...
    unpack_folded_state(dynamic_dsm);

stop_no_dsm = find(max_r_no_dsm == 0, 1, 'first');
stop_dsm = find(max_r_dsm == 0, 1, 'first');
stop_dynamic = find(max_r_dynamic == 0, 1, 'first');

if isempty(stop_dynamic)
    cycle_updates = cfg.max_updates;
else
    cycle_updates = stop_dynamic;
end

% Red B拍 + commit + Black B拍 + commit + CHECK
fixed_cycles = cycle_updates * (2 * hw.data_width + 3);
dynamic_cycles = sum( ...
    2 * dynamic_width_trace(1:cycle_updates) + 3);
cycle_speedup = fixed_cycles / dynamic_cycles;

change_updates = [1; ...
    find(diff(dynamic_width_trace) ~= 0) + 1];

fprintf('\n===== raw bit-vector 模型结果 =====\n');
fprintf('寄存器 MATLAB 容器类型：%s\n', ...
    class(u_final_dynamic_bits));
fprintf('寄存器 raw bits 范围：0 ~ %d\n', ...
    2^hw.data_width - 1);
fprintf('定点格式：signed Q%d.%d\n', ...
    hw.data_width - hw.frac_width - 1, ...
    hw.frac_width);
fprintf('FP64 理想解收敛轮数：%d\n', ideal_updates);
fprintf('无 DSM residue 归零：%s\n', ...
    number_or_not_found(stop_no_dsm));
fprintf('DSM residue 归零：%s\n', ...
    number_or_not_found(stop_dsm));
fprintf('动态 DSM residue 归零：%s\n', ...
    number_or_not_found(stop_dynamic));
fprintf('无 DSM 最终 MAE：%.9f\n', mae_no_dsm(end));
fprintf('DSM 最终 MAE：%.9f\n', mae_dsm(end));
fprintf('动态 DSM 最终 MAE：%.9f\n', mae_dynamic(end));
fprintf('动态位宽切换：');

for index = 1:numel(change_updates)
    change_update = change_updates(index);
    fprintf('第%d轮=%d-bit', ...
        change_update, dynamic_width_trace(change_update));
    if index < numel(change_updates)
        fprintf('，');
    else
        fprintf('\n');
    end
end

fprintf('固定 16-bit 周期：%d\n', fixed_cycles);
fprintf('动态位宽周期：%d\n', dynamic_cycles);
fprintf('计入 CHECK 后的周期加速：%.3f 倍\n', ...
    cycle_speedup);

assert(isequal(u_final_dynamic_bits, u_final_dsm_bits), ...
    '动态位宽最终 solution bits 不一致。');
assert(isequal(r_final_dynamic_bits, r_final_dsm_bits), ...
    '动态位宽最终 residue bits 不一致。');

%% 绘图
colors = [0.18, 0.48, 0.75; ...
          0.86, 0.33, 0.24; ...
          0.48, 0.28, 0.68];

figure('Color', 'w', 'Name', 'Raw bit-vector result', ...
    'Position', [120, 120, 1080, 430]);

subplot(1, 2, 1);
semilogy(1:cfg.max_updates, mae_no_dsm, ...
    'LineWidth', 1.8, 'Color', colors(1, :));
hold on;
semilogy(1:cfg.max_updates, mae_dsm, ...
    'LineWidth', 1.8, 'Color', colors(2, :));
semilogy(1:cfg.max_updates, mae_dynamic, ':', ...
    'LineWidth', 2.2, 'Color', colors(3, :));
xlabel('红黑更新轮数');
ylabel('MAE');
title('Raw bit-vector bit-equivalent 结果');
legend('固定 16-bit', '固定 16-bit + DSM', ...
    '动态位宽 + DSM', 'Location', 'northeast');
ax = gca;
ax.GridAlpha = 0.14;
ax.XGrid = 'off';
ax.YGrid = 'on';
ax.XMinorGrid = 'off';
ax.YMinorGrid = 'off';

subplot(1, 2, 2);
stairs(1:cycle_updates, ...
    dynamic_width_trace(1:cycle_updates), ...
    'LineWidth', 2.0, 'Color', colors(3, :));
ylim([3, 17]);
yticks([4, 8, 12, 16]);
xlabel('红黑更新轮数');
ylabel('本轮 residue 位宽');
title(sprintf('动态位宽，周期加速 %.2f 倍', ...
    cycle_speedup));
ax = gca;
ax.GridAlpha = 0.14;
ax.XGrid = 'off';
ax.YGrid = 'on';


%% 初始化 Red/Black 折叠寄存器
function state = init_folded_state( ...
    n_rows, n_cols, boundary_bits, hw)

    state.n_rows = n_rows;
    state.n_cols = n_cols;
    state.n_pairs = ceil(n_cols / 2);

    % 所有 *_bits 字段都保存寄存器原始位模式
    state.grid_r_bits = boundary_bits;

    pe_size = [n_rows, state.n_pairs];
    state.r_red_bits = zeros(pe_size);
    state.r_black_bits = zeros(pe_size);
    state.u_red_bits = zeros(pe_size);
    state.u_black_bits = zeros(pe_size);
    state.e_red_bits = zeros(pe_size);
    state.e_black_bits = zeros(pe_size);

    % 以下只是 MATLAB 网格映射元数据
    state.valid_red = zeros(pe_size);
    state.valid_black = zeros(pe_size);
    state.red_col = zeros(pe_size);
    state.black_col = zeros(pe_size);

    for row = 1:n_rows
        for col = 1:n_cols
            pair = ceil(col / 2);
            if mod(row + col, 2) == 0
                state.valid_red(row, pair) = 1;
                state.red_col(row, pair) = col;
            else
                state.valid_black(row, pair) = 1;
                state.black_col(row, pair) = col;
            end
        end
    end

    validate_folded_state(state, hw);
end


%% 一个完整 Red/Black 更新
function next = folded_pe_step_bits( ...
    state, active_width, use_dsm, hw)

    next = state;
    next.r_red_bits(:) = 0;
    next.r_black_bits(:) = 0;

    % Red phase：Black residue 是 source
    for row = 1:state.n_rows
        for pair = 1:state.n_pairs
            if state.valid_red(row, pair) == 1
                col = state.red_col(row, pair);
                [r_n, r_s, r_e, r_w] = ...
                    read_four_neighbor_bits(state, row, col);

                [next.r_red_bits(row, pair), ...
                 next.e_red_bits(row, pair)] = ...
                    average_alu_bits( ...
                    r_n, r_s, r_e, r_w, ...
                    state.e_red_bits(row, pair), ...
                    active_width, use_dsm, hw);
            end
        end
    end

    % Black phase：新 Red residue 是 source
    for row = 1:state.n_rows
        for pair = 1:state.n_pairs
            if state.valid_black(row, pair) == 1
                col = state.black_col(row, pair);
                [r_n, r_s, r_e, r_w] = ...
                    read_four_neighbor_bits(next, row, col);

                [next.r_black_bits(row, pair), ...
                 next.e_black_bits(row, pair)] = ...
                    average_alu_bits( ...
                    r_n, r_s, r_e, r_w, ...
                    state.e_black_bits(row, pair), ...
                    active_width, use_dsm, hw);
            end
        end
    end

    % 二进制补码加法器：直接对 raw bits 做 W-bit 模加法
    next.u_red_bits = hw_add_bits( ...
        state.u_red_bits, next.r_red_bits, ...
        hw.data_width, 'u_red_add');
    next.u_black_bits = hw_add_bits( ...
        state.u_black_bits, next.r_black_bits, ...
        hw.data_width, 'u_black_add');

    % 边界 residue 只注入第一轮
    next.grid_r_bits(:) = 0;

    validate_folded_state(next, hw);
end


%% B-bit 共享平均值 ALU
function [r_new_full_bits, e_new_bits] = ...
    average_alu_bits( ...
    r_n_full, r_s_full, r_e_full, r_w_full, ...
    e_prev_bits, active_width, use_dsm, hw)

    full_inputs = [ ...
        r_n_full, r_s_full, r_e_full, r_w_full];
    hw_assert_raw_bits(full_inputs, ...
        hw.data_width, 'neighbor_full_bits');

    sum_width = active_width + hw.sum_guard_bits;
    sum_bits = 0;
    expected_sum_value = 0;

    for input_index = 1:4
        % 取 active_width 个低位，等价于本轮只发送 B 个 bit
        narrow_bits = hw_low_bits( ...
            full_inputs(input_index), active_width, ...
            'neighbor_narrow_bits');

        full_value = hw_bits_to_signed( ...
            full_inputs(input_index), hw.data_width, ...
            'neighbor_full_bits');
        narrow_value = hw_bits_to_signed( ...
            narrow_bits, active_width, ...
            'neighbor_narrow_bits');

        % 阈值必须保证删除的高位全部是冗余符号扩展位
        assert(full_value == narrow_value, ...
            '%d-bit 模式截掉了有效符号位。', ...
            active_width);

        operand_sum_bits = hw_sign_extend_bits( ...
            narrow_bits, active_width, sum_width, ...
            'operand_sum_bits');
        sum_bits = hw_add_bits( ...
            sum_bits, operand_sum_bits, sum_width, ...
            'sum_b_plus_2');
        expected_sum_value = ...
            expected_sum_value + full_value;
    end

    if use_dsm
        hw_assert_raw_bits(e_prev_bits, ...
            hw.dsm_width, 'dsm_error_bits');

        % DSM error 是 unsigned 2-bit，向 B+2 bit 零扩展
        dsm_sum_bits = hw_zero_extend_bits( ...
            e_prev_bits, hw.dsm_width, sum_width, ...
            'dsm_sum_bits');
        sum_bits = hw_add_bits( ...
            sum_bits, dsm_sum_bits, sum_width, ...
            'sum_with_dsm');
        expected_sum_value = ...
            expected_sum_value + e_prev_bits;
    end

    actual_sum_value = hw_bits_to_signed( ...
        sum_bits, sum_width, 'sum_bits');
    hw_assert_signed_value(expected_sum_value, ...
        sum_width, 'expected_sum_value');
    assert(actual_sum_value == expected_sum_value, ...
        'B+2 bit 求和结果与数学结果不一致。');

    % 对 B+2 bit raw vector 进行真正的符号补位右移
    shifted_sum_bits = hw_asr_bits( ...
        sum_bits, sum_width, 2, 'sum_asr_2');

    % quotient 只保留低 B 位，再符号扩展回 16-bit residue bank
    r_new_narrow_bits = hw_low_bits( ...
        shifted_sum_bits, active_width, ...
        'residue_narrow_bits');
    r_new_full_bits = hw_sign_extend_bits( ...
        r_new_narrow_bits, active_width, ...
        hw.data_width, 'residue_full_bits');

    if use_dsm
        % 除以 4 丢掉的两位就是 sum_bits[1:0]
        e_new_bits = hw_low_bits( ...
            sum_bits, hw.dsm_width, ...
            'dsm_error_next_bits');

        % 在 B+2 bit 内验证：(r_new << 2) + error == sum
        r_in_sum_bits = hw_sign_extend_bits( ...
            r_new_narrow_bits, active_width, ...
            sum_width, 'residue_in_sum_width');
        reconstructed_bits = hw_lsl_bits( ...
            r_in_sum_bits, sum_width, 2, ...
            'residue_lsl_2');
        reconstructed_bits = hw_add_bits( ...
            reconstructed_bits, e_new_bits, ...
            sum_width, 'dsm_reconstructed_sum');

        assert(reconstructed_bits == sum_bits, ...
            'DSM raw bits 守恒关系错误。');
    else
        e_new_bits = 0;
    end
end


%% 动态位宽检测
function active_width = select_dynamic_width( ...
    state, widths, thresholds, hw)

    residue_full_bits = [ ...
        state.r_red_bits(:); ...
        state.r_black_bits(:); ...
        state.grid_r_bits(:)];

    residue_values = hw_bits_to_signed( ...
        residue_full_bits, hw.data_width, ...
        'dynamic_residue_bits');
    peak_value = max(abs(residue_values));

    active_width = widths(1);
    for index = numel(widths):-1:1
        if peak_value <= thresholds(index)
            active_width = widths(index);
            break;
        end
    end
end


%% 折叠网格读取
function [r_n, r_s, r_e, r_w] = ...
    read_four_neighbor_bits(state, row, col)

    r_n = read_folded_residue_bits( ...
        state, row - 1, col);
    r_s = read_folded_residue_bits( ...
        state, row + 1, col);
    r_e = read_folded_residue_bits( ...
        state, row, col + 1);
    r_w = read_folded_residue_bits( ...
        state, row, col - 1);
end


function bits = read_folded_residue_bits( ...
    state, row, col)

    if row < 1 || row > state.n_rows || ...
            col < 1 || col > state.n_cols
        bits = state.grid_r_bits(row + 1, col + 1);
        return;
    end

    pair = ceil(col / 2);
    if mod(row + col, 2) == 0
        assert(state.valid_red(row, pair) == 1 && ...
               state.red_col(row, pair) == col, ...
               'Red 映射错误。');
        bits = state.r_red_bits(row, pair);
    else
        assert(state.valid_black(row, pair) == 1 && ...
               state.black_col(row, pair) == col, ...
               'Black 映射错误。');
        bits = state.r_black_bits(row, pair);
    end
end


function [u_bits, r_bits] = ...
    unpack_folded_state(state)

    u_bits = zeros(state.n_rows, state.n_cols);
    r_bits = zeros(state.n_rows, state.n_cols);

    for row = 1:state.n_rows
        for pair = 1:state.n_pairs
            if state.valid_red(row, pair) == 1
                col = state.red_col(row, pair);
                u_bits(row, col) = ...
                    state.u_red_bits(row, pair);
                r_bits(row, col) = ...
                    state.r_red_bits(row, pair);
            end

            if state.valid_black(row, pair) == 1
                col = state.black_col(row, pair);
                u_bits(row, col) = ...
                    state.u_black_bits(row, pair);
                r_bits(row, col) = ...
                    state.r_black_bits(row, pair);
            end
        end
    end
end


%% 定点输入输出
function bits = fx_encode_signed_bits( ...
    physical_value, width, frac_width, signal_name)

    signed_value = round( ...
        physical_value * (2^frac_width));
    hw_assert_signed_value( ...
        signed_value, width, signal_name);
    bits = hw_signed_to_bits( ...
        signed_value, width, signal_name);
end


function physical_value = fx_decode_signed_bits( ...
    bits, width, frac_width)

    signed_value = hw_bits_to_signed( ...
        bits, width, 'fixed_point_bits');
    physical_value = signed_value / (2^frac_width);
end


%% Raw bit-vector 硬件原语
function sum_bits = hw_add_bits( ...
    a_bits, b_bits, width, signal_name)
% W-bit 加法器，只保留低 W 位。

    hw_assert_raw_bits(a_bits, width, signal_name);
    hw_assert_raw_bits(b_bits, width, signal_name);

    sum_bits = mod(a_bits + b_bits, 2^width);
    hw_assert_raw_bits(sum_bits, width, signal_name);
end


function low_bits = hw_low_bits( ...
    input_bits, output_width, signal_name)
% 等价于 Verilog input_bits[output_width-1:0]。

    hw_assert_integer_double(input_bits, signal_name);
    validate_width(output_width);

    low_bits = mod(input_bits, 2^output_width);
    hw_assert_raw_bits( ...
        low_bits, output_width, signal_name);
end


function output_bits = hw_zero_extend_bits( ...
    input_bits, input_width, output_width, signal_name)

    assert(output_width >= input_width, ...
        '零扩展的输出位宽不能小于输入位宽。');
    hw_assert_raw_bits( ...
        input_bits, input_width, signal_name);

    output_bits = input_bits;
    hw_assert_raw_bits( ...
        output_bits, output_width, signal_name);
end


function output_bits = hw_sign_extend_bits( ...
    input_bits, input_width, output_width, signal_name)

    assert(output_width >= input_width, ...
        '符号扩展的输出位宽不能小于输入位宽。');

    signed_value = hw_bits_to_signed( ...
        input_bits, input_width, signal_name);
    output_bits = hw_signed_to_bits( ...
        signed_value, output_width, signal_name);
end


function output_bits = hw_asr_bits( ...
    input_bits, width, shift_amount, signal_name)
% 对 raw W-bit vector 执行 Verilog signed >>> shift_amount。

    hw_assert_raw_bits( ...
        input_bits, width, signal_name);
    validate_shift_amount(shift_amount);

    sign_bit = floor( ...
        input_bits / (2^(width - 1)));

    if shift_amount == 0
        output_bits = input_bits;
    elseif shift_amount >= width
        output_bits = sign_bit * (2^width - 1);
    else
        logical_shifted = floor( ...
            input_bits / (2^shift_amount));
        high_fill_mask = ...
            (2^shift_amount - 1) * ...
            2^(width - shift_amount);
        output_bits = logical_shifted + ...
            sign_bit * high_fill_mask;
    end

    hw_assert_raw_bits( ...
        output_bits, width, signal_name);
end


function output_bits = hw_lsl_bits( ...
    input_bits, width, shift_amount, signal_name)
% 对 raw W-bit vector 执行 Verilog <<，只保留低 W 位。

    hw_assert_raw_bits( ...
        input_bits, width, signal_name);
    validate_shift_amount(shift_amount);

    output_bits = mod( ...
        input_bits * (2^shift_amount), 2^width);
    hw_assert_raw_bits( ...
        output_bits, width, signal_name);
end


function bits = hw_signed_to_bits( ...
    signed_value, width, signal_name)
% signed 数值转换为 W-bit two's-complement raw bits。

    hw_assert_signed_value( ...
        signed_value, width, signal_name);

    bits = mod(signed_value, 2^width);
    hw_assert_raw_bits(bits, width, signal_name);
end


function signed_value = hw_bits_to_signed( ...
    bits, width, signal_name)
% W-bit raw bits 按 two's-complement 解释为 signed 数值。

    hw_assert_raw_bits(bits, width, signal_name);

    signed_value = bits;
    sign_mask = bits >= 2^(width - 1);
    signed_value(sign_mask) = ...
        signed_value(sign_mask) - 2^width;

    hw_assert_signed_value( ...
        signed_value, width, signal_name);
end


function hw_assert_raw_bits(bits, width, signal_name)

    validate_width(width);
    hw_assert_integer_double(bits, signal_name);

    assert(all(bits(:) >= 0 & ...
               bits(:) <= 2^width - 1), ...
        '%s 不是合法的 %d-bit raw vector。', ...
        signal_name, width);
end


function hw_assert_signed_value( ...
    signed_value, width, signal_name)

    validate_width(width);
    hw_assert_integer_double( ...
        signed_value, signal_name);

    lower_limit = -2^(width - 1);
    upper_limit = 2^(width - 1) - 1;
    assert(all(signed_value(:) >= lower_limit & ...
               signed_value(:) <= upper_limit), ...
        '%s 超出 signed %d-bit 范围 [%g, %g]。', ...
        signal_name, width, lower_limit, upper_limit);
end


function hw_assert_integer_double(value, signal_name)

    assert(isa(value, 'double'), ...
        '%s 必须由 MATLAB double 保存 raw bits。', ...
        signal_name);
    assert(all(isfinite(value(:))), ...
        '%s 出现 NaN 或 Inf。', signal_name);
    assert(all(value(:) == floor(value(:))), ...
        '%s 出现非整数 bit pattern。', signal_name);
end


function validate_width(width)
% double 可以精确表示到 2^53，本模型限制到 52 bit。

    assert(isa(width, 'double') && isscalar(width), ...
        '位宽必须是 MATLAB double 标量。');
    assert(width >= 1 && width <= 52 && ...
           width == floor(width), ...
        '位宽必须是 1~52 的整数。');
end


function validate_shift_amount(shift_amount)

    assert(isa(shift_amount, 'double') && ...
           isscalar(shift_amount), ...
        '移位量必须是 MATLAB double 标量。');
    assert(shift_amount >= 0 && ...
           shift_amount == floor(shift_amount), ...
        '移位量必须是非负整数。');
end


%% 配置和状态检查
function validate_hw_spec(hw)

    validate_width(hw.data_width);
    validate_width(hw.dsm_width);

    assert(hw.frac_width >= 0 && ...
           hw.frac_width < hw.data_width && ...
           hw.frac_width == floor(hw.frac_width), ...
        '小数位宽配置错误。');
    assert(hw.sum_guard_bits == 2, ...
        '四个 signed residue 求和需要两个 guard bits。');
    assert(all(hw.dynamic_widths <= hw.data_width), ...
        '动态位宽不能超过 residue bank 位宽。');
    assert(numel(hw.dynamic_widths) == ...
           numel(hw.dynamic_thresholds), ...
        '动态位宽和阈值数量不一致。');

    safe_thresholds = ...
        2.^(hw.dynamic_widths - 1) - 1;
    assert(all(hw.dynamic_thresholds <= ...
               safe_thresholds), ...
        '动态阈值超过对应 signed 位宽。');
end


function validate_folded_state(state, hw)

    hw_assert_raw_bits(state.grid_r_bits, ...
        hw.data_width, 'grid_r_bits');
    hw_assert_raw_bits(state.r_red_bits, ...
        hw.data_width, 'r_red_bits');
    hw_assert_raw_bits(state.r_black_bits, ...
        hw.data_width, 'r_black_bits');
    hw_assert_raw_bits(state.u_red_bits, ...
        hw.data_width, 'u_red_bits');
    hw_assert_raw_bits(state.u_black_bits, ...
        hw.data_width, 'u_black_bits');
    hw_assert_raw_bits(state.e_red_bits, ...
        hw.dsm_width, 'e_red_bits');
    hw_assert_raw_bits(state.e_black_bits, ...
        hw.dsm_width, 'e_black_bits');
end


function run_bit_vector_self_test()
% 检查 raw bits、补码、符号扩展和移位。

    assert(hw_signed_to_bits(-1, 8, ...
        'signed_to_bits_test') == 255);
    assert(hw_bits_to_signed(255, 8, ...
        'bits_to_signed_test') == -1);

    minus_five_bits = hw_signed_to_bits( ...
        -5, 8, 'minus_five_bits');
    minus_two_bits = hw_asr_bits( ...
        minus_five_bits, 8, 2, 'asr_test');
    assert(minus_two_bits == 254);
    assert(hw_bits_to_signed( ...
        minus_two_bits, 8, 'asr_test') == -2);

    assert(hw_asr_bits(5, 8, 2, ...
        'positive_asr_test') == 1);
    assert(hw_add_bits(255, 1, 8, ...
        'add_wrap_test') == 0);
    assert(hw_lsl_bits(128, 8, 1, ...
        'lsl_wrap_test') == 0);

    minus_one_4b = hw_signed_to_bits( ...
        -1, 4, 'minus_one_4b');
    minus_one_16b = hw_sign_extend_bits( ...
        minus_one_4b, 4, 16, ...
        'sign_extend_test');
    assert(minus_one_4b == 15);
    assert(minus_one_16b == 65535);

    q16_16_below_one = fx_encode_signed_bits( ...
        1 - 2^-16, 32, 16, 'q16_16_test');
    q16_16_one = fx_encode_signed_bits( ...
        1, 32, 16, 'q16_16_test');
    assert(q16_16_below_one == 65535);
    assert(q16_16_one == 65536);
end


%% FP64 理想参考解
function [u_ideal, update] = solve_ideal_solution( ...
    boundary_physical, tol, max_updates)

    u = boundary_physical;
    converged = false;

    for update = 1:max_updates
        u_old = u;

        for row = 2:size(u, 1) - 1
            for col = 2:size(u, 2) - 1
                if mod(row + col, 2) == 0
                    u(row, col) = ...
                        (u(row - 1, col) + ...
                         u(row + 1, col) + ...
                         u(row, col - 1) + ...
                         u(row, col + 1)) / 4;
                end
            end
        end

        for row = 2:size(u, 1) - 1
            for col = 2:size(u, 2) - 1
                if mod(row + col, 2) == 1
                    u(row, col) = ...
                        (u(row - 1, col) + ...
                         u(row + 1, col) + ...
                         u(row, col - 1) + ...
                         u(row, col + 1)) / 4;
                end
            end
        end

        if max(abs(u(:) - u_old(:))) <= tol
            converged = true;
            break;
        end
    end

    assert(converged, ...
        'FP64 理想参考解没有收敛。');
    u_ideal = u(2:end-1, 2:end-1);
end


function text_value = number_or_not_found(value)

    if isempty(value)
        text_value = '未找到';
    else
        text_value = sprintf('%d', value);
    end
end
