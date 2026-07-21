%EXPLORE_BATCH2 双上下文交错的算法级吞吐上限。
% 本脚本只统计算术更新槽，不模拟 Fig. 8 的位串行通信。
% 2 倍结果是理想上限，真实硬件还需要双状态、独立发送缓存和足够带宽。

clear; clc;
here = fileparts(mfilename('fullpath'));
addpath(here);
addpath(fullfile(here, '..', 'func'));

N = 9;
tol = 1e-3;
initial_u = zeros(N+2, N+2);
initial_u(1,:) = 1;
initial_u(end,:) = 1;
initial_u(:,1) = 1;
initial_u(:,end) = 1;
mae = @(u) mean(abs(reshape(u(2:end-1, 2:end-1), [], 1) - 1));

% 统计两个颜色相位中的 PE 数量。
[I, J] = ndgrid(1:N+2, 1:N+2);
interior = false(N+2);
interior(2:end-1, 2:end-1) = true;
num_even = nnz(interior & mod(I+J, 2) == 0);
num_odd = nnz(interior & mod(I+J, 2) == 1);
num_pe = N^2;

% 基线：两道问题依次执行。
solo_updates = solve_laplace(@checkerboard_step, N, tol, 1000);
serial_cycles = 4 * solo_updates;
serial_arithmetic_occupancy = (num_even + num_odd) / (2 * num_pe);

% 理想交错：忽略通信和状态端口冲突。
u_a = initial_u;
u_b = initial_u;
done_a = 0;
done_b = 0;
cycle = 0;
busy_slots = 0;
while ~done_a || ~done_b
    cycle = cycle + 1;
    if mod(cycle, 2) == 1
        if ~done_a
            u_a = checkerboard_halfstep(u_a, 0);
            busy_slots = busy_slots + num_even;
        end
        if ~done_b
            u_b = checkerboard_halfstep(u_b, 1);
            busy_slots = busy_slots + num_odd;
        end
    else
        if ~done_a
            u_a = checkerboard_halfstep(u_a, 1);
            busy_slots = busy_slots + num_odd;
        end
        if ~done_b
            u_b = checkerboard_halfstep(u_b, 0);
            busy_slots = busy_slots + num_even;
        end
        if ~done_a && mae(u_a) <= tol
            done_a = cycle;
        end
        if ~done_b && mae(u_b) <= tol
            done_b = cycle;
        end
    end
end

interleaved_cycles = max(done_a, done_b);
interleaved_arithmetic_occupancy = busy_slots / (interleaved_cycles * num_pe);

fprintf('单个问题：%d 轮完整更新（%d 个颜色相位）\n', ...
    solo_updates, 2*solo_updates);
fprintf('两个问题串行：%d 个相位，算术槽占用率 %.1f%%\n', ...
    serial_cycles, 100*serial_arithmetic_occupancy);
fprintf('理想交错执行：%d 个相位，算术槽占用率 %.1f%%\n', ...
    interleaved_cycles, 100*interleaved_arithmetic_occupancy);
fprintf('算法级吞吐上限：%.2fx\n', ...
    serial_cycles/interleaved_cycles);
fprintf('以上结果未计入额外硬件和通信冲突。\n');
