function plotParamPosteriors(ensemble, idx)
posterior       = ensemble.samples;   
                  posterior(idx);

for param_idx     = param_idxs
    paramName     = ensemble.paramMap{param_idx}; 
    param_samples = ensemble.samples(:, param_idx);    
    auto_corr     = autocorr(param_samples, maxLag);
    figure();
    plot(auto_corr); 
    xlabel('lag');    
    title(['Auto-Correlation: ' paramName]);
end 

end 