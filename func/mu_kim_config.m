function cfg = mu_kim_config()
%MU_KIM_CONFIG 集中保存全部实验参数。

cfg.convergence.grid_size = 9;
cfg.convergence.mae_target = 1e-3;
cfg.convergence.max_updates = 1000;

cfg.quantization.grid_size = 20;
cfg.quantization.num_updates = 640;
cfg.quantization.bits = [16, 24];

N = cfg.convergence.grid_size;
cfg.methods = struct( ...
    'name',              {'Jacobi', 'Hybrid', 'Gauss-Seidel', 'Checkerboard'}, ...
    'value_step',        {@jacobi_step, @hybrid_step, @gauss_seidel_step, @checkerboard_step}, ...
    'residue_step',      {@residue_jacobi_step, @residue_hybrid_step, ...
                          @residue_gauss_seidel_step, @residue_checkerboard_step}, ...
    'cycles_per_update', {1, N, N^2, 2});
end
