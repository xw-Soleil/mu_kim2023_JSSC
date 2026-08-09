function [k, mae_hist, r_hist, u] = solve_laplace_residue(step_fn, N, tol, max_iter)
%SOLVE_LAPLACE_RESIDUE 按论文式 (6)–(7) 进行 residue 迭代。
% 边界值只作为初始 residue 注入，r_hist 记录每轮最大 residue。

u = zeros(N+2, N+2);
r = zeros(N+2, N+2);
r(1,:)   = 1;
r(end,:) = 1;
r(:,1)   = 1;
r(:,end) = 1;

mae_hist = zeros(1, max_iter);
r_hist = zeros(1, max_iter);
for k = 1:max_iter
    [u, r] = step_fn(u, r);
    interior = u(2:end-1, 2:end-1);
    mae_hist(k) = mean(abs(interior(:) - 1));
    r_hist(k) = max(abs(r(:)));
    if mae_hist(k) <= tol
        break
    end
end
mae_hist = mae_hist(1:k);
r_hist = r_hist(1:k);
end
