function u_new = sor_checkerboard_step(u, w)
%SOR_CHECKERBOARD_STEP 值域模型中的红黑 SOR 更新。
% w=1 时退化为普通 checkerboard；不模拟定点量化和 RTL 额外状态。

[nr, nc] = size(u);
[I, J] = ndgrid(1:nr, 1:nc);
red    = mod(I+J, 2) == 0;
inner  = false(nr, nc);
inner(2:end-1, 2:end-1) = true;

u_new = u;
avg = neighbor_avg(u_new);            % 第 1 拍:红点
m = inner & red;
u_new(m) = (1-w)*u_new(m) + w*avg(m);
avg = neighbor_avg(u_new);            % 第 2 拍:黑点,用红点新值
m = inner & ~red;
u_new(m) = (1-w)*u_new(m) + w*avg(m);
end

function a = neighbor_avg(x)
a = zeros(size(x));
a(2:end-1,2:end-1) = ( x(1:end-2, 2:end-1) + x(3:end,   2:end-1) ...
                     + x(2:end-1, 1:end-2) + x(2:end-1, 3:end  ) ) / 4;
end
