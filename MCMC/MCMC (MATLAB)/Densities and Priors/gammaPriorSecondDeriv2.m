function prior_prob_matrix = gammaPriorSecondDeriv2(numSampledParams,...
                                                   sampled_params,  ...
                                                   shape)
% pi_{param,param} = - (k-1) / x^2
 prior_prob_matrix = diag(  (- shape*ones(1, numSampledParams) + ...
                               ones(1, numSampledParams)         ...
                            )                                    ...
                            ./ sampled_params.^2                 ...
                         );

end


