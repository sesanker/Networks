% plots confidence trajectories for confidence region bound

function plotTrajectoryConfidence(ensemble)

states             =  ensemble.trajectoryQuantiles.statesToPlot;
timePoints         =  ensemble.timePoints;

for i = 1: length(states)    
    stateNames{i}  =  ensemble.stateMap{states(i)}; 
end

plotConfidence = @(mean, lower, upper, color) ...
                                               ...
                   set(fill([mean,  fliplr(mean)],  ...
                            [upper, fliplr(lower)], ...
                            color                   ...
                           ),                       ...
                          'EdgeColor', color);

for i = 1: length(states)
    quantile_trajs = trajectoryQuantiles(ensemble, states(i));
    upper          = quantile_trajs{1};
    mean           = quantile_trajs{2};
    lower          = quantile_trajs{3};
   
    figure(50 + i);
    plotConfidence(timePoints, lower, upper, 'g');
    hold on;
    plot(timePoints, mean);    
    hXlabel = xlabel('time'); 
    hYlabel = ylabel(stateNames{i});
    hTitle  = title(['95% confidence interval for : '...
                     stateNames{i}]); 
                 
    set([hXlabel, hYlabel,  hTitle], 'FontName', 'AvantGarde');
    
    set([hXlabel, hYlabel], 'FontSize',  12, ...
                            'FontWeight', 'bold');
    set(hTitle,             'FontSize',  13, ...
                            'FontWeight', 'bold');

end % for

end % function
