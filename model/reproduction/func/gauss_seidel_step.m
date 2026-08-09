function u_new = gauss_seidel_step(u)
%GAUSS_SEIDEL_STEP 一轮 Gauss-Seidel 更新，对应论文式 (9)。
% 按行扫描，上、左读取新值，下、右读取旧值。

u_new = u;
[nr, nc] = size(u);

for i = 2:nr-1
    for j = 2:nc-1
        u_new(i,j) = (u_new(i-1,j) + u(i+1,j) + ...
                      u_new(i,j-1) + u(i,j+1)) / 4;
    end
end
end
