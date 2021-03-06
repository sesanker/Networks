function prior_prob_matrix = FHN_prior_second_deriv(numSampledParams,...
                                                    sampled_params)

 prior_prob_matrix = diag( - 2*ones(1, numSampledParams)...
                           ./ sampled_params.^2         ...
                         );

end


