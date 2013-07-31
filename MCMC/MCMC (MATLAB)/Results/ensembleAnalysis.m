% Returns a struct of ensemble analysis functions

function ensAnalysisObject = ensembleAnalysis()

% add all files in current directory
addpath(genpath('./'));
ensembleAnalysis.calculateESS             = @calculateESS;
ensembleAnalysis.plotTraces               = @plotTraces;
ensembleAnalysis.plotAutoCorrelations     = @plotAutoCorrelations;
ensembleAnalysis.plotRunningMeans         = @plotRunningMeans; 
ensembleAnalysis.plotParameterQuantiles   = @plotParameterQuantiles;
ensembleAnalysis.plotTrajectoryQuantiles  = @plotTrajectoryQuantiles;
ensembleAnalysis.plot2dParamSlices        = @plot2dParamSlices;
ensembleAnalysis.plot3dParamSlices        = @plot3dParamSlices;
ensembleAnalysis.plotAcceptanceRatios     = @plotAcceptanceRatios;
ensembleAnalysis.plotLogLikelihoodRatios  = @plotLogLikelihoodRatios;
ensembleAnalysis.plotNewOldOldNewRatios   = @NewOldOldNewRatios;
ensembleAnalysis.GeometricStructure       = geometricStructure(); % returns a struct of functions

ensAnalysisObject = ensembleAnalysis;
end

