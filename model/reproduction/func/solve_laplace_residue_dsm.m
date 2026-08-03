function [k, mae_hist, r_hist, u] = solve_laplace_residue_dsm(step_fn, N, tol, max_iter)
%SOLVE_LAPLACE_RESIDUE_DSM 带 DSM 误差状态 q 的 residue 求解器。

u = zeros(N+2, N+2);
r = zeros(N+2, N+2);
r(1,:)   = 1;
r(end,:) = 1;
r(:,1)   = 1;
r(:,end) = 1;
q = zeros(N+2, N+2);

mae_hist = zeros(1, max_iter);
r_hist   = zeros(1, max_iter);
for k = 1:max_iter
    [u, r, q] = step_fn(u, r, q);
    inner = u(2:end-1, 2:end-1);
    mae_hist(k) = mean(abs(inner(:) - 1));
    r_hist(k)   = max(abs(r(:)));
    if mae_hist(k) <= tol
        break
    end
end
mae_hist = mae_hist(1:k);
r_hist   = r_hist(1:k);
end
