function plotTrajectoryQuantiles(ensemble)

quantiles         =  ensemble.trajQuantiles;
numQuantiles      =  length(quantiles)
 
% Trajectories are rows, timePoints are columns
trajectories      = ensemble.trajectories;
sortedTrajs       = sort(trajectories);
timePoints        = columns(sortedTrajs);
quantile_trajs    = cell(numQuantiles)

for i  = 1: numQuantiles    
    
    q     = quantiles(i);
    index = q * timePoints;
    
    if isinteger(index)
        quantile_trajs{i} = sortedTrajs(:, index);
    else
        floor_idx = floor(index);
        ceil_idx  = ceil(index);
        q_floor   = floor_idx / timePoints;
        q_ceil    = ceil_idx  / timePoints;
        
        quantile_trajs{i} = sortedTrajs(floor_idx, :) + ((q - q_floor) / (q_ceil - q_floor)) *...
                                                                                              ...
                                                        (sortedTrajs(ceil_idx, :) - sortedTrajs(floor_idx, :))
    
    figure();
    plot(rm); 
    xlabel('posterior sample number'); 
    ylabel('mean');
    title(['Running Mean: ' paramName]);
    
end % for

end 
