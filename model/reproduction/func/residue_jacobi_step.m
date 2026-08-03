function [u_new, r_new] = residue_jacobi_step(u, r)
%RESIDUE_JACOBI_STEP residue 形式的 Jacobi 更新。
% 新 residue 为邻居平均值，并累加到解 u 中。

r_new = zeros(size(r));
[nr, nc] = size(r);

for i = 2:nr-1
    for j = 2:nc-1
        r_new(i,j) = (r(i-1,j) + r(i+1,j) + ...
                      r(i,j-1) + r(i,j+1)) / 4;
    end
end
u_new = u + r_new;
end
