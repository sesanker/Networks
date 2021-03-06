% Get sensitivities Function:
% Returns a cell array of matrices. The columns of each matrix 
% holds the trajectory of (X_p)' for some species X and parameter p 
% The indexing of the sensitivities assumes the sensitivity equations 
% are given in a particular order in the model file

function [Sens1, Sens2] = get_Sensitivities_Analytic(sensTrajectories,... 
                                                     NumOfSpecies,... 
                                                     numSampledParams...
                                                    )
    if nargin == 3
       zeroSens_2 = false;
    end
    
    Sensitivities_1 = cell(1, numSampledParams);
    Sensitivities_2 = cell(numSampledParams, numSampledParams);
    
    for j = 1 : numSampledParams
    % Get first order sensitivities of all species with respect to parameter j
        Sensitivities_1{j} = sensTrajectories(:, ...
                                              (NumOfSpecies*j) + 1  :...
                                              (NumOfSpecies*(j + 1))...
                                             );
    end 
    
    if zeroSens_2   
        
       Sens1 = Sensitivities_1;
       return;  
            
    else   
        for j = 1 : numSampledParams      
            % Get second order sensitivities of all species with respect to parameters j and k
            for k = j : numSampledParams
                CurrentStartIndex   = ( NumOfSpecies*(numSampledParams + 1) +... 
                                        (sum(1:numSampledParams) -... 
                                         sum(1:numSampledParams - (j - 1))...
                                        ) * NumOfSpecies... 
                                      )...
                                      + (k - j)*NumOfSpecies + 1;
                
                Sensitivities_2{j, k} = sensTrajectories(:, CurrentStartIndex:(...
                                                                           CurrentStartIndex + ...
                                                                           (NumOfSpecies - 1)...
                                                                          ));
                Sensitivities_2{k, j} = Sensitivities_2{j, k};            
            end % for
            
        end % for
    end % if       
            Sens1 = Sensitivities_1;
            Sens2 = Sensitivities_2;
end % function


