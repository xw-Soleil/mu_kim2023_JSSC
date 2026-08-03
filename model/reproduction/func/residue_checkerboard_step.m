function [u_new, r_new] = residue_checkerboard_step(u, r)
%RESIDUE_CHECKERBOARD_STEP residue 形式的红黑棋盘格更新。
% 两个颜色相位结束后清除边界 residue。

[nr, nc] = size(r);
[I, J] = ndgrid(1:nr, 1:nc);
red    = mod(I+J, 2) == 0;
inner  = false(nr, nc);
inner(2:end-1, 2:end-1) = true;

r_new = zeros(nr, nc);
r_new([1 end], :) = r([1 end], :);
r_new(:, [1 end]) = r(:, [1 end]);

avg = neighbor_avg(r);               % 第一相位：偶数色。
r_new(inner & red)  = avg(inner & red);
avg = neighbor_avg(r_new);           % 第二相位：奇数色。
r_new(inner & ~red) = avg(inner & ~red);

r_new([1 end], :) = 0;
r_new(:, [1 end]) = 0;
u_new = u + r_new;
end

function a = neighbor_avg(x)
% 计算每个内部点的四邻居平均值。
a = zeros(size(x));
a(2:end-1,2:end-1) = (x(1:end-2, 2:end-1) + x(3:end, 2:end-1) + ...
                       x(2:end-1, 1:end-2) + x(2:end-1, 3:end)) / 4;
end
