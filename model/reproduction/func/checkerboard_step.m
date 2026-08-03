function u_new = checkerboard_step(u)
%CHECKERBOARD_STEP 一轮红黑棋盘格更新，共两个颜色相位。
% 红点读取旧值，随后黑点读取红点的新值。

u_new = u;
[nr, nc] = size(u);

% 第一相位：更新偶数色。
for i = 2:nr-1
    for j = 2:nc-1
        if mod(i+j, 2) == 0
            u_new(i,j) = (u(i-1,j) + u(i+1,j) + ...
                          u(i,j-1) + u(i,j+1)) / 4;
        end
    end
end

% 第二相位：更新奇数色。
for i = 2:nr-1
    for j = 2:nc-1
        if mod(i+j, 2) == 1
            u_new(i,j) = (u_new(i-1,j) + u_new(i+1,j) + ...
                          u_new(i,j-1) + u_new(i,j+1)) / 4;
        end
    end
end
end
