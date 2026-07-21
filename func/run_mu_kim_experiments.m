function results = run_mu_kim_experiments(cfg)
%RUN_MU_KIM_EXPERIMENTS 运行全部数值实验，不负责输出和绘图。

if nargin == 0
    cfg = mu_kim_config();
end

methods = cfg.methods;
num_methods = numel(methods);
N = cfg.convergence.grid_size;
tol = cfg.convergence.mae_target;
max_updates = cfg.convergence.max_updates;

results.config = cfg;
results.method_names = {methods.name};
results.iterations = zeros(1, num_methods);
results.mae = cell(1, num_methods);
results.residue_iterations = zeros(1, num_methods);
results.residue_mae = cell(1, num_methods);
results.max_residue = cell(1, num_methods);
results.solution_difference = zeros(1, num_methods);

for method_id = 1:num_methods
    [k_value, mae_value, u_value] = solve_laplace( ...
        methods(method_id).value_step, N, tol, max_updates);
    [k_residue, mae_residue, max_residue, u_residue] = ...
        solve_laplace_residue(methods(method_id).residue_step, ...
                              N, tol, max_updates);

    interior = 2:(N + 1);
    results.iterations(method_id) = k_value;
    results.mae{method_id} = mae_value;
    results.residue_iterations(method_id) = k_residue;
    results.residue_mae{method_id} = mae_residue;
    results.max_residue{method_id} = max_residue;
    results.solution_difference(method_id) = max(abs( ...
        u_value(interior, interior) - u_residue(interior, interior)), [], 'all');
end

results.pe_updates = results.iterations * N^2;
results.cycle_proxy = results.iterations .* [methods.cycles_per_update];

% Fig. 11 和 Fig. 13 对应的定点 checkerboard 实验。
Nq = cfg.quantization.grid_size;
num_updates = cfg.quantization.num_updates;
bits = cfg.quantization.bits;

[~, results.quantization.float_mae] = solve_laplace_residue( ...
    @residue_checkerboard_step, Nq, 0, num_updates);

results.quantization.bits = bits;
results.quantization.no_dsm_mae = cell(1, numel(bits));
results.quantization.dsm_mae = cell(1, numel(bits));
for bit_id = 1:numel(bits)
    word_length = bits(bit_id);
    quantized_step = @(u, r) residue_checkerboard_qstep( ...
        u, r, word_length);
    dsm_step = @(u, r, q) residue_checkerboard_qdsm_step( ...
        u, r, q, word_length);

    [~, results.quantization.no_dsm_mae{bit_id}] = ...
        solve_laplace_residue(quantized_step, Nq, 0, num_updates);
    [~, results.quantization.dsm_mae{bit_id}] = ...
        solve_laplace_residue_dsm(dsm_step, Nq, 0, num_updates);
end

results.quantization.final_float = results.quantization.float_mae(end);
results.quantization.final_no_dsm = cellfun(@(x) x(end), ...
    results.quantization.no_dsm_mae);
results.quantization.final_dsm = cellfun(@(x) x(end), ...
    results.quantization.dsm_mae);
results.quantization.improvement = results.quantization.final_no_dsm ./ ...
                                   results.quantization.final_dsm;
end
