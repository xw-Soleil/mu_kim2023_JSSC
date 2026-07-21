function [u_new, r_new] = residue_checkerboard_qstep(u, r, nbits)
%RESIDUE_CHECKERBOARD_QSTEP 定点量化的红黑棋盘格更新。
% 除以 4 时使用 floor，模拟硬件右移产生的截断误差。

LSB = 2^(1 - nbits);
[nr, nc] = size(r);
[I, J] = ndgrid(1:nr, 1:nc);
red    = mod(I+J, 2) == 0;
inner  = false(nr, nc);
inner(2:end-1, 2:end-1) = true;

r_new = zeros(nr, nc);
r_new([1 end], :) = r([1 end], :);
r_new(:, [1 end]) = r(:, [1 end]);

avg = neighbor_avg_q(r, LSB);        % 第一相位：偶数色。
r_new(inner & red)  = avg(inner & red);
avg = neighbor_avg_q(r_new, LSB);    % 第二相位：奇数色。
r_new(inner & ~red) = avg(inner & ~red);

r_new([1 end], :) = 0;
r_new(:, [1 end]) = 0;
u_new = u + r_new;
end

function a = neighbor_avg_q(x, LSB)
% 计算四邻居平均，并量化到 LSB 的整数倍。
a = zeros(size(x));
s = x(1:end-2, 2:end-1) + x(3:end, 2:end-1) + ...
    x(2:end-1, 1:end-2) + x(2:end-1, 3:end);
a(2:end-1, 2:end-1) = LSB * floor(s / (4 * LSB));
end
