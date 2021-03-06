% Run network 5.2

% Add all dierectories in MCMC methods to path
addpath(genpath('./'))
% Close all Figures
close all;

Model.burnin                = 1;
Model.numPosteriorSamples   = 200;


% name for saving results
Model.equationName                   = 'network_fiveDotTwo'; 
% function handle of model for automatic differentiation
Model.equations                      = @network_fiveDotTwo;
Model.equations_AD                   = @network_fiveDotTwo_AD;
% indexes of observed species in state vector
Model.observedStates                 = [1 2 3 4 5];
Model.unobservedStates               = [];
Model.totalStates                    = 1:5;
% indexes of sampled parameters 
% All other parameters are held fixed
Model.numTotalParams                 = 29;
sampledParam_idxs                    = [1:3:21];
Model.numSampledParams               = length(sampledParam_idxs);
Model.sampledParam_idxs              = sampledParam_idxs;
% Noise
Model.addedNoise_SD                  = .5;
% Scale factor used in tempering
Model.beta                           = 1e-6;
% The initial step size for parameter updates
Model.initialStepSize                = ;
Model.stepMax                        = Model.initialStepSize;
Model.stepMin                        = .1;
% Step Size for standard Metropolis Hastings
Model.mhStepSize                     = 1e-3 / Model.beta;
% The step size is adjusted online until acceptance ratio
% is in the range given by 'stepSizeRange'
Model.stepSizeRange                  = [70 80];
% Adjust Step-Size after stepSizeMonitorRate iterations
Model.stepSizeMonitorRate            = 3;
% epsilon is for finite differences
Model.epsilon                        = 5e-1; 
Model.zeroMetricTensorDerivatives    = true;
% If true plots trajectories for all proposed parameters
Model.plotProposedTrajectories       = true;
% Use basic MALA algorithm without manifold information
Model.isMala                         = false;
% Number of steps to recalculate metric tensor (can set to 'randomWalk')
Model.tensorMonitorRate              = 1;
% Preconditioning matrix that don't use 
Model.preConditionMatrix             = eye(Model.numSampledParams);
%                                        inv(1e4*[4.0493   -5.3057   -0.8575
%                                        -5.3057    8.3806    1.5185
%                                        -0.8575    1.5185    0.2977]);


% For RMHMC
Model.numLeapFrogSteps               = 3;
Model.stepSize_RMHMC                 = 2 / Model.numLeapFrogSteps;
Model.maxFixedPointStepsMomentum     = 5;
Model.maxFixedPointStepsPosition     = 3;
% Use basic HMC without manifold information
Model.isHMC                          = false;

% Choose sensitvity type
sensitivityMethods                   = getSensitivityMethods();
% 1 = symbolic, 2= finite diff, 3= automatic diff
Model.sensitivityMethod              = sensitivityMethods{3};


% Model specific priors (function handles))
% The Prior Struct holds all information regarding priors

% Used in calculating prior probabilities of current and proposed parameters
% must implement @(param_num, param)
Prior.prior     = @(paramNum, param) ...
                    uninformedSupportPrior(paramNum, ...
                                           param,... 
                                           1:(Model.numTotalParams),...
                                           [0, 1e7]); % support
                                    
% Used in computing natural gradient of posterior
Prior.priorDerivative         = @genericZeroedPriorDeriv;
% Used in computing the metric tensor of posterior
Prior.priorSecondDerivative   = @genericZeroedPriorSecondDeriv;
% Used in computing the derivative of metric tensor for the Laplace
% Beltrami Operator
Prior.priorThirdDerivative    = @genericZeroedPriorThirdDeriv;

Model.Prior                   = Prior;

% Model specific integration settings
numTimePts    = 200;
startTime     = 0;
endTime       = 200;
step          = (endTime - startTime) / numTimePts;
timePoints    = startTime: step :endTime;

A_initial =  568;
B_initial =  324; 
C_initial =  251;
D_initial =  152; 
E_initial =  268;

initialValues = [ A_initial...
                  B_initial...
                  C_initial...
                  D_initial... 
                  E_initial];         

% All 29 network_fiveDotTwo parameters 
k1 = 400;  k2 = 400;  k3 = 300;  k4 = 300;  k5 = 300;  k6 = 300;  k7 = 300;
n1 = 4;    n2 = 4;    n3 = 4;    n4 = 4;    n5 = 4;    n6 = 4;    n7 = 4;
a1 = 50;   a2 = 50;   a3 = 100;  a4 = 100;  a5 = 50;
b1 = 0.06; b2 = 0.06; b3 = 0.06; b4 = 0.06; b5 = 0.06;
y1 = 0.1;  y2 = 0.1;  y3 = 0.1;  y4 = 0.1;  y5 = 0.1;

params =     [...
               k1 k2 k3 k4 k5 k6 k7 ...               
               n1 n2 n3 n4 n5 n6 n7 ...
               a1 a2 a3 a4 a5...
               b1 b2 b3 b4 b5...
               y1 y2 y3 y4 y5...              
             ];

% Cell array of all parameter names         
paramMap = {...
               'k1' 'k2' 'k3' 'k4' 'k5' 'k6' ...               
               'n1' 'n2' 'n3' 'n4' 'n5' 'n6' ...
               'a1' 'a2' 'a3' 'a4' 'a5'      ...
               'b1' 'b2' 'b3' 'b4' 'b5'      ...
               'y1' 'y2' 'y3' 'y4' 'y5'      ...              
           };
           
stateMap = {'A' 'B' 'C' 'D' 'E'};

% Param Triples fro online plotting
Model.paramTriple_idxs = {... 
                          [1  4 6 ],... 
                          [2  5 3 ],...
                          [7  2 4 ]...
                         }; 
    
Model.totalParams        = params;
Model.numTotalParams     = length(params);
Model.paramMap           = paramMap;
Model.stateMap           = stateMap;
Model.initialValues      = initialValues;

% Integrate model equations
[timeData, speciesEstimates] = ode45( Model.equations  ,...
                                      timePoints,...
                                      initialValues,...      
                                      odeset('RelTol', 1e-6),...
                                      params);

Model.timeData          = timeData' ; % note the transposes here
speciesEstimates        = speciesEstimates' ;
Model.speciesEstimates  = speciesEstimates;

[numStates, numTimePts] = size(speciesEstimates);

% Add Noise to trajectories
addedNoise_SD    = Model.addedNoise_SD;
Model.noisyData  = speciesEstimates + ...
                   randn(numStates, numTimePts) .* addedNoise_SD;

%%%%%%%%%%%%%%%%%%%%%%%%%        
% Call sampling routines %
%%%%%%%%%%%%%%%%%%%%%%%%%


% MH(Model);
% MH_oneParamAt_a_Time(Model);
  MALA(Model);
% RMHMC(Model);

%%%%%%%%%%%%%%%%%%%%%%%%%        
% For ensemble analysis %
%%%%%%%%%%%%%%%%%%%%%%%%%

% 95%, 50% and 5% confidence intervals on trajectories
Model.trajQuantiles                    = [.975 .5 .025];
Model.paramQuantiles.params            = Model.sampledParam_idxs;
Model.trajectoryQuantiles.statesToPlot = Model.totalStates;
Model.posteriorParamsToPlot            = Model.sampledParam_idxs;
ensembleData                           = load(['mMALA_' Model.equationName]);
ensembleAnalysis(Model, ensembleData);















