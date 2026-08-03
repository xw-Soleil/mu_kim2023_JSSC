function u_new = checkerboard_halfstep(u, color)
%CHECKERBOARD_HALFSTEP 只更新棋盘格中的一个颜色。
% color=0 表示偶数色，color=1 表示奇数色；不模拟 PE 通信和端口冲突。

[nr, nc] = size(u);
[I, J] = ndgrid(1:nr, 1:nc);
m      = mod(I+J, 2) == color;
inner  = false(nr, nc);
inner(2:end-1, 2:end-1) = true;

avg = neighbor_avg(u);
u_new = u;
u_new(inner & m) = avg(inner & m);
end

function a = neighbor_avg(x)
a = zeros(size(x));
a(2:end-1,2:end-1) = ( x(1:end-2, 2:end-1) + x(3:end,   2:end-1) ...
                     + x(2:end-1, 1:end-2) + x(2:end-1, 3:end  ) ) / 4;
end
