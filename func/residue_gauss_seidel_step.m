function [u_new, r_new] = residue_gauss_seidel_step(u, r)
%RESIDUE_GAUSS_SEIDEL_STEP residue 形式的 Gauss-Seidel 更新。
% 上、左读取本轮 residue，下、右读取上一轮 residue。

r_new = zeros(size(r));
r_new([1 end], :) = r([1 end], :);
r_new(:, [1 end]) = r(:, [1 end]);
[nr, nc] = size(r);

for i = 2:nr-1
    for j = 2:nc-1
        r_new(i,j) = (r_new(i-1,j) + r(i+1,j) + ...
                      r_new(i,j-1) + r(i,j+1)) / 4;
    end
end

r_new([1 end], :) = 0;
r_new(:, [1 end]) = 0;
u_new = u + r_new;
end
