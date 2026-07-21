function [k, mae_hist, u] = solve_laplace(step_fn, N, tol, max_iter)
%SOLVE_LAPLACE 求解边界为 1、内部初值为 0 的二维 Laplace 问题。

u = zeros(N+2, N+2);
u(1,:)   = 1;
u(end,:) = 1;
u(:,1)   = 1;
u(:,end) = 1;

mae_hist = zeros(1, max_iter);
for k = 1:max_iter
    u = step_fn(u);
    inner = u(2:end-1, 2:end-1);
    mae_hist(k) = mean(abs(inner(:) - 1));
    if mae_hist(k) <= tol
        break
    end
end
mae_hist = mae_hist(1:k);
end
