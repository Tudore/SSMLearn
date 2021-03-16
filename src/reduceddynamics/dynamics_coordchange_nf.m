function Maps = dynamics_coordchange_nf(Maps_info,opt_options)
% Minimization of the invariance equation for a normal form coordinate
% change in a dynamical systems. For a flow, the invariance equation reads
%
%                 DT^{-1}(y_k)\dot{y}_k = N(T^{-1}(y_k))
%
% while for a map
%  
%                 T^{-1}(y_{k+1}) = N(T^{-1}(y_k)).
%
% in which 
%
%                 z = T^{-1}(y) = y + W_it_nl \phi_it(y)
%                 N(z) = Dz +  W_n_nl \phi_it(y)
%
% where the unknowns are the coefficients W_it_nl, W_n_nl, determined via
% an unconstrained optimization process. D is a known diagonal matrix. The
% optimization minimizes the squared error between the left and the right
% sides of the invariance equation.
% The routine consider oscillatory normal forms only, in complex
% coordinates. Constraints on the the normal form coefficients have been
% computed previously so that the optimization only tackles the necessary
% coefficients.
% The other mapping y = T(z) is obtained via simple regression. Ultimately,
% the maps T and T^{-1} are expressed in physical coordinates
% for output and input respectively through a linear coordinates change V.

% Define function to minimize
fun = @(z) f_minimize(z,Maps_info,opt_options.L2);

% Define options for the optimization algorithm
opt_options_fm = optimoptions('fminunc',...
    'Display',opt_options.Display,...
    'OptimalityTolerance',opt_options.OptimalityTolerance,...
    'MaxIterations',opt_options.MaxIter,...
    'MaxFunctionEvaluations',opt_options.MaxFunctionEvaluations,...
    'SpecifyObjectiveGradient',opt_options.SpecifyObjectiveGradient,...
    'CheckGradients',opt_options.CheckGradients);
if opt_options.IC_nf == 0
    Maps_info.IC_opt = 0*Maps_info.IC_opt;
end
% Run unconstrained optimization
z = fminunc(fun,Maps_info.IC_opt,opt_options_fm);
% Final output
N_info = Maps_info.N; iT_info = Maps_info.iT;
% Nonlinear Maps & Dimensions
phi_n_nl = N_info.phi; phi_it_nl = iT_info.phi;
[phi_dim_n,k] = size(N_info.Exponents);
phi_dim_it = size(iT_info.Exponents,1); k_red = size(Maps_info.Yk_r,1);
V = Maps_info.V;
% Indexes
idx_n = N_info.idx; idx_it = iT_info.idx;
z_complex = z(1:length(z)/2)+1i*z(length(z)/2+1:end);
% Reshape optimization vector
W_it = [eye(k_red) full(sparse(idx_it(:,1),idx_it(:,2),z_complex(...
    1:size(idx_it,1)),size(Maps_info.Yk_r,1),phi_dim_it))];
W_n  = [diag(Maps_info.d_r) full(sparse(idx_n(:,1),idx_n(:,2),z_complex(...
    size(idx_it,1)+[1:size(idx_n,1)]),size(Maps_info.Yk_r,1),phi_dim_n))];
phi_it = @(y) [y(1:k_red,:); phi_it_nl(y)];
phi_n = @(y) [y(1:k_red,:); phi_n_nl(y)];
iT = @(x) cc_transf(W_it*phi_it(V\x));
N = @(z) cc_transf(W_n*phi_n(z));
% Get the transformation T
Zk = cc_transf(Maps_info.Yk_r+W_it(:,k_red+1:end)*Maps_info.Phi_iT_Yk);
[phi_t_nl,Expmat_t] = multivariate_polynomial(k,2,opt_options.T_PolyOrd);
[W_t_nl,~,~] = ridgeregression(phi_t_nl(Zk),Maps_info.Yk_r-Zk(1:k_red,:),...
    opt_options.L2,[],0);
phi_t = @(z) [z(1:k_red,:); phi_t_nl(z)];
W_t = [eye(k_red) W_t_nl];
T = @(z) 2*real(V(:,1:k_red)*W_t*phi_t(z));
% Storing
eye_red = eye(k); eye_red = eye_red(1:k_red,:); 
iT_info = struct('Map',iT,'coeff',W_it,'phi',phi_it,'Exponents',...
                                             [eye_red; iT_info.Exponents]);
T_info = struct('Map',T,'coeff',W_t,'phi',phi_t,'Exponents',...
                                                      [eye_red; Expmat_t]);
N_info = struct('Map',N,'coeff',W_n,'phi',phi_n,'Exponents',...
                                              [eye_red; N_info.Exponents]);
Maps = struct('iT',iT_info,'N',N_info,'T',T_info,'V',V);
end

%- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

function [f,Df] = f_minimize(z,Maps_info,L2)
N_info = Maps_info.N; iT_info = Maps_info.iT;
% Nonlinear Maps & Dimensions
phi_n = N_info.phi; [phi_dim_n,k] = size(N_info.Exponents);
phi_dim_it = size(iT_info.Exponents,1); k_red = size(Maps_info.Yk_r,1);
% Indexes
idx_n = N_info.idx; idx_it = iT_info.idx;
z_complex = z(1:length(z)/2)+1i*z(length(z)/2+1:end);
% Reshape optimization vector
W_it_nl = sparse(idx_it(:,1),idx_it(:,2),z_complex(1:size(idx_it,1)),...
    k_red,phi_dim_it);
W_n_nl  = sparse(idx_n(:,1),idx_n(:,2),z_complex(size(idx_it,1)+...
    [1:size(idx_n,1)]),k_red,phi_dim_n);
% Compute function
Phi_iT_Yk = Maps_info.Phi_iT_Yk; iTk_nl = W_it_nl*Phi_iT_Yk; 
iTk = cc_transf(Maps_info.Yk_r + iTk_nl); Phi_N = phi_n(iTk);
Err = Maps_info.Yk_1_DYk_r + W_it_nl*Maps_info.Phi_iT_Yk_1 - ...
    (Maps_info.d_r.*iTk_nl + W_n_nl*Phi_N);
f = sum(sum((Err.*conj(Err)).*L2))/size(Maps_info.Yk_r,2)/k;
if nargout > 1 % gradient required
    cErr_L = conj(Err).*L2;
    lidx_n = N_info.lidx; lidx_it = iT_info.lidx;
    Dphi_n_info = Maps_info.D_phi_n_info;
    % Derivative with respect to W_it_nl
    DF_it = +cErr_L*transpose(Maps_info.Phi_iT_Yk_1) + ...
        -(Maps_info.d_r.*cErr_L)*transpose(Phi_iT_Yk) ;
    DF_it_re = real(DF_it); DF_it_im = -imag(DF_it);
    % Nonlinear part
    DF_it_re_nl = zeros(size(W_it_nl)); DF_it_im_nl = zeros(size(W_it_nl));
    for ii = 1:k_red
        Di_phi_n = Dphi_n_info(ii).Derivative; Di_Phi_N = Di_phi_n(iTk);
        Di_Phi_N = [Di_Phi_N; ...
                       zeros(phi_dim_n-size(Di_Phi_N,1),size(Di_Phi_N,2))];
        Di_Phi_N = Di_Phi_N(Dphi_n_info(ii).Indexes,:);
        term_i = (sum(cErr_L.*(W_n_nl*Di_Phi_N),1)*...
                                                     transpose(Phi_iT_Yk));
        DF_it_re_nl(ii,:) = DF_it_re_nl(ii,:) + term_i;
        DF_it_im_nl(ii,:) = DF_it_im_nl(ii,:) + 1i*term_i;
    end
    for ii = k_red+1:k
        Di_phi_n = Dphi_n_info(ii).Derivative; Di_Phi_N = Di_phi_n(iTk);
        Di_Phi_N = [Di_Phi_N; ...
                       zeros(phi_dim_n-size(Di_Phi_N,1),size(Di_Phi_N,2))];
        Di_Phi_N = Di_Phi_N(Dphi_n_info(ii).Indexes,:);
        term_i = (sum(cErr_L.*(W_n_nl*Di_Phi_N),1)*...
                                               transpose(conj(Phi_iT_Yk)));
        DF_it_re_nl(ii-k_red,:) = DF_it_re_nl(ii-k_red,:) + term_i;
        DF_it_im_nl(ii-k_red,:) = DF_it_im_nl(ii-k_red,:) - 1i*term_i;
    end
    DF_it_re = DF_it_re - real(DF_it_re_nl);
    DF_it_im = DF_it_im - real(DF_it_im_nl);
    % Derivative with respect to W_n_nl
    DF_n = -cErr_L*transpose(Phi_N);
    DF_n_re = real(DF_n); DF_n_im = -imag(DF_n);
    % Final reshaping of the derivative
    Df = 2*[reshape(DF_it_re(lidx_it),length((lidx_it)),1); ...
            reshape(DF_n_re(lidx_n),length((lidx_n)),1);...
            reshape(DF_it_im(lidx_it),length((lidx_it)),1); ...
            reshape(DF_n_im(lidx_n),length((lidx_n)),1)]...
            /size(Maps_info.Yk_r,2)/k;
end
end
