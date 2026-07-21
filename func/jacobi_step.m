function u_new = jacobi_step(u)
%JACOBI_STEP 一轮 Jacobi 更新，对应论文式 (8)。
% 所有内部点只读取上一轮邻居值，边界保持不变。

u_new = u;
[nr, nc] = size(u);

for i = 2:nr-1
    for j = 2:nc-1
        u_new(i,j) = (u(i-1,j) + u(i+1,j) + ...
                      u(i,j-1) + u(i,j+1)) / 4;
    end
end
end
