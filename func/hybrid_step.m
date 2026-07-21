function u_new = hybrid_step(u)
%HYBRID_STEP 一轮 Hybrid 更新，对应论文 Fig. 5 右上。
% 行内使用旧值，已完成的上一行使用新值。

u_new = u;
[nr, nc] = size(u);

for i = 2:nr-1
    for j = 2:nc-1
        u_new(i,j) = (u_new(i-1,j) + u(i+1,j) + ...
                      u(i,j-1) + u(i,j+1)) / 4;
    end
end
end
