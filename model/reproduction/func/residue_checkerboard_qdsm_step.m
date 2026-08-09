function [u_new, r_new, q] = residue_checkerboard_qdsm_step(u, r, q, nbits)
%RESIDUE_CHECKERBOARD_QDSM_STEP 带一阶 DSM 的定点棋盘格更新。
% q 保存除以 4 时的截断误差，并反馈到该 PE 的下一次计算：
%   sum_eff = neighbor_sum + q_old
%   r_new   = floor(sum_eff / (4*LSB)) * LSB
%   q_new   = sum_eff - 4*r_new

LSB = 2^(1 - nbits);
[nr, nc] = size(r);
[I, J] = ndgrid(1:nr, 1:nc);
red    = mod(I+J, 2) == 0;
inner  = false(nr, nc);
inner(2:end-1, 2:end-1) = true;

r_new = zeros(nr, nc);
r_new([1 end], :) = r([1 end], :);
r_new(:, [1 end]) = r(:, [1 end]);

% 第一相位：偶数色读取上一轮 residue。
s  = neighbor_sum(r);
sq = s + q;
rq = LSB * floor(sq / (4*LSB));
mask = inner & red;
r_new(mask) = rq(mask);
q(mask) = sq(mask) - 4*r_new(mask);

% 第二相位：奇数色读取偶数色刚生成的 residue。
s  = neighbor_sum(r_new);
sq = s + q;
rq = LSB * floor(sq / (4 * LSB));
mask = inner & ~red;
r_new(mask) = rq(mask);
q(mask) = sq(mask) - 4*r_new(mask);

r_new([1 end], :) = 0;
r_new(:, [1 end]) = 0;
u_new = u + r_new;
end

function s = neighbor_sum(x)
% 计算四邻居之和，输出尺寸与输入一致。
s = zeros(size(x));
s(2:end-1,2:end-1) = x(1:end-2, 2:end-1) + x(3:end, 2:end-1) + ...
                       x(2:end-1, 1:end-2) + x(2:end-1, 3:end);
end
