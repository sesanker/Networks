% Returns a struct of ensemble analysis functions
% Analysis of one MCMC ensemble
% add all files in current directory

function ensembleAnalysis(Model, ensembleData)

addpath(genpath('./'));

ensemble.autoCorr.maxLags      = [];
ensemble.ESS.isTimeNormalized  = true;
ensemble.posteriorTime         = ensembleData.posteriorTime;
ensemble.autoCorr.params       = Model.sampledParam_idxs(:) ;
ensemble.paramMap              = Model.paramMap;
ensemble.samples               = ensembleData.paramHistory;
% 95%, 50% and 5% confidence intervals
ensemble.trajQuantiles         = Model.trajQuantiles;
% Trajectories are rows, timePoints are columns
ensemble.trajectories          = ensembleData.trajectoryHistory;
ensemble.stateMap              = Model.stateMap;
ensemble.paramQuantiles.params = Model.paramQuantiles.params;
ensemble.posteriorParamsToPlot = Model.posteriorParamsToPlot;
ensemble.timePoints            = Model.timeData;
% Number of bins to use in posterior param plot
ensemble.posteriorParamPlotBins   = 200;
ensemble.posteriorParamAxisRanges = {[5.3 6.3 0 9], [5.3 6.3 0 9], [5.3 6.3 0 9]}; %Model.posteriorParamAxisRanges;{[5 10], [5 10], [5 10]};

ensemble.trajectoryQuantiles.statesToPlot = Model.trajectoryQuantiles.statesToPlot;

%%%%%%%%%%%%%%%%%%%%%%%%%        
% Statistics and Plots  %
%%%%%%%%%%%%%%%%%%%%%%%%%
[minESS, meanESS,...
 maxESS, totalESS]  = calculateESS(ensemble);

disp('Effective Sample Size: ');
disp('%%%%');
disp(['(minESS): '   num2str(minESS) ]);
disp(['(meanESS): '  num2str(meanESS) ]);
disp(['(maxESS): '   num2str(maxESS) ]);
disp(['(totalESS): ' num2str(totalESS) ]);
disp('%%%%');
  
plotAutoCorrelations(ensemble);
plotTrajectoryConfidence(ensemble);
plotParamPosteriors(ensemble);
figStart = 500;
plot3dParamSlices(ensemble.samples, figStart);



