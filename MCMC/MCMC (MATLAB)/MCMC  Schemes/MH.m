function  MH(Model)

% Start the timer for burn-in samples
tic
% Print variable output to terminal in real time
more off; 
% Note: state variables are called 'species'
% Y is the experimental data we are trying to fit
Y = Model.noisyData;
[numStates, numTimePts] = size(Y);


% Set Model specifications
% Observed and unobserved species are vectors
% with indexes of state variables
% 'Equations' is a function handle of ODE and
% sensitivity equations
% sampled parameters are the parameters 
% that will be sampled with MCMC
% numSampledParams is the # of parameters
% used in MCMC sampling
numSampledParams                   = Model.numSampledParams;
numTotalParams                     = Model.numTotalParams;
observedStates                     = Model.observedStates;
unobservedStates                   = Model.unobservedStates;
totalStates                        = length(observedStates) + ...
                                     length(unobservedStates);
addedNoise_SD                      = Model.addedNoise_SD;
equations                          = Model.equations;
equations_AD                       = Model.equations_AD;
initialValues                      = Model.initialValues;

stepSize                           = Model.mhStepSize;  
stepSizeRange                      = Model.stepSizeRange; 

burnin                             = Model.burnin;
numPosteriorSamples                = Model.numPosteriorSamples;
equationName                       = Model.equationName;
totalParams                        = Model.totalParams;
timePoints                         = Model.timeData;
numTimePoints                      = length(timePoints);
plotProposedTrajectories           = Model.plotProposedTrajectories;

sampledParam_idxs                  = Model.sampledParam_idxs;
sampledParams                      = totalParams(sampledParam_idxs);                                          
beta                               = Model.beta;



% Model specific priors:
% Prior struct of priors and derivatives
% Objective priors throw exceptions when parameters reach
% regions of zero probability
Prior                   = Model.Prior;     
% Used in calculating prior probabilities of current and proposed parameters
prior                   = Prior.prior;
% Used in computing the metric tensor of posterior
priorSecondDerivative   = Prior.priorSecondDerivative;



% Set up noise for likelihood function
% Fix noise - CurrentNoise is the variance
% Note: we are cheating here the noise of 
% the likelihood is set to  noise added to the  
% synthetic data
% if SDNoise is a scalar, the same noise is added to each 
% species. Otherwise assume it's a vector of noises for
% each species. Technically the noise can be a matrix for
% each time point for each species
if isscalar(addedNoise_SD)
    currentNoise = ones(1, numStates) * addedNoise_SD^2;
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Calculate metric tensor and maximum likelihood values of parameters     %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 

% initialize parameters to throw away values to use getSensAndTrajectories 
% function
zeroMetricTensorDerivatives = true;
sensitivityMethod           = 'automatic differentiation';
equationsSens               = {};
initialValuesSens           = [];
epsilon                     = NaN; 

if strcmp(Model.tensorMonitorRate,...
         'randomWalk')
         
    % set monitor rate greater than total number of samples
    tensorMonitorRate = burnin + numPosteriorSamples + 1;
    M                 = Model.preConditionMatrix;
    
    [ ~ , trajectories] = ...
                          ...
                      ode45(...
                             equations,... 
                             timePoints,... 
                             initialValues,...   
                             odeset('RelTol', 1e-6),...                   
                             totalParams...
                           );       


        % Ocassionally  trajectories may get imaginary artifacts                   
        if any(imag(trajectories(:)))
            error('Trajectory has imaginary components');
        end % if

        speciesEstimates  = extractSpeciesTrajectories(trajectories,...
                                                       numStates);  
else
    tensorMonitorRate = Model.tensorMonitorRate;
    % calculate 1st and 2nd order sensitivities
    [trajectories,      ...
     sensitivities_1,   ...
           ~        ] = ...
                        ...
                  getSensAndTrajectories...
                                        ...
                            ( sensitivityMethod,   zeroMetricTensorDerivatives,...
                              equations,           equations_AD,               ...  
                              equationsSens,                                   ... 
                              initialValues,       initialValuesSens,          ...
                              timePoints,          numStates,                  ...  
                              numSampledParams,    totalParams,                ...
                              sampledParam_idxs,   epsilon                     ...                                 
                            );

    speciesEstimates  = extractSpeciesTrajectories(trajectories,...
                                                   numStates);
    % calculate 1st and 2nd order sensitivities                     
    currentG = metricTensor(...
                             sampledParams,    sensitivities_1,... 
                             numSampledParams, observedStates,... 
                             currentNoise,     priorSecondDerivative...                              
                           );

    identity           = eye(numSampledParams);    
    % In addition to bounding singular values
    % add diagonal dust to improve rank                                      
    currentInvG        = identity / (currentG + identity*1e-6);

    M                  = currentInvG;
    M_invProposed      = currentG;
    
end % if

current_LL   = calculate_LL( speciesEstimates, Y,... 
                             currentNoise,     observedStates...
                           );                     


currentSampledParams       = sampledParams;
currentSpeciesEstimates    = speciesEstimates;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Initialize constants and allocate arrays for Manifold MALA              %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Set up accepted / rejected proposal counters
accepted  = 0;
attempted = 0;

% Allocate Histories, LL is for log likelihood
paramHistory        = zeros(numPosteriorSamples, numSampledParams);
LL_History          = zeros(numPosteriorSamples, numStates);
trajectoryHistory   = zeros(numStates, numPosteriorSamples, numTimePoints);

% Set monitor rate for adapting step sizes
stepSizeMonitorRate = Model.stepSizeMonitorRate;

% Initialize ratioLastAccepted to 1 in case there is no previous accepted
% step
ratioLastAccepted     = 1;
% initialize current stepSize
currentStepSize            = stepSize;

% Allocate vector to store acceptance ratios
acceptanceRatios    = zeros(1, burnin +...
                            numPosteriorSamples);
% Converged to posterior
converged           = false;
% Set up converged flag
continueIterations  = true;
% Initialize iteration number
iterationNum        = 0;
                      
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%              MALA Algorithm to sample the parameters:                   %
%          All proposed parameters lack a 'Current' prefix                %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

while continueIterations    
    
    iterationNum    = iterationNum + 1;      
 
    calculateTensor = mod(iterationNum, ...
                          tensorMonitorRate) == 0; 
    
    attempted       = attempted    + 1; 
    
    disp(['Iteration:  '...
          num2str(iterationNum)]);
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Update parameters       %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%      
    
    newSampledParams  = currentSampledParams + ...
                                               ...
                        randn(1, numSampledParams) * chol(stepSize*M); 
    
    newParams         = updateTotalParameters( totalParams,...
                                               newSampledParams,...
                                               sampledParam_idxs);     
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Integrate Equations     %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%    
    
    if calculateTensor
        
        try
        
            [trajectories,      ...
             sensitivities_1,   ...
                   ~        ] = ...
                                     ...
                      getSensAndTrajectories...
                                            ...
                                ( sensitivityMethod, zeroMetricTensorDerivatives,...
                                  equations,         equations_AD,               ...  
                                  equationsSens,                                 ... 
                                  initialValues,     initialValuesSens,          ...
                                  timePoints,        numStates,             ...  
                                  numSampledParams,  newParams,             ...
                                  sampledParam_idxs, epsilon                ...                                 
                                ); 
                            
              G               = metricTensor(...
                                             newSampledParams,   sensitivities_1,... 
                                             numSampledParams,   observedStates,... 
                                             currentNoise,       priorSecondDerivative...                              
                                            );

             speciesEstimates  = extractSpeciesTrajectories(trajectories,...
                                                           numStates);             
        catch
            disp('!!! INTEGRATION ERROR !!!');
            iterationNum = iterationNum - 1;  
            attempted    = attempted    - 1;
            
            % initialize condition number so it goes through one iteration
            conditionNumBound = 1e8;
            conditionNumber_1 = conditionNumBound;
            conditionNumber_2 = conditionNumBound;
            % redo current iteration step 
            identity = eye(numSampledParams);
            testInvG = identity / (G + identity*1e-6);
            
            while conditionNumber_1 > conditionNumBound && ...
                  conditionNumber_2 > conditionNumBound
              
                disp('rescaling matrix');
                if (randn > 0.5) stepSign = 1; else stepSign = -1; end
                stepSize = max(- Model.stepMax, ...
                                 min(Model.stepMax, ...
                                     stepSize + stepSign*rand*Model.stepMax...
                                    )...
                              );      

                conditionNumber_1 =  1 / rcond(stepSize*M);
                conditionNumber_2 =  1 / rcond(stepSize*testInvG);
                
                
            end
                
            continue;
        end % try         

        
       
                                  
        identity    = eye(numSampledParams); 
        % In addition to bounding singular values
        % add diagonal dust to improve rank                                       
        invG        =  identity / (G + identity*1e-6);
        
        % Keep track of old and new sampling matricies for acceptance ratio         
        % in proposal distribution
        M_invCurrent  = M_invProposed; % previous G
        M_invProposed = G;
        
        M_current     =  M;        
        M_proposed    =  invG;
        M             =  M_proposed;
        
        
%         currentSampledParams  = newSampledParams;
        
%         newSampledParams      = currentSampledParams + ...
%                                                        ...
%                                 randn(1, numSampledParams) * chol(stepSize*M); 
    
%         newParams             = updateTotalParameters( totalParams,...
%                                                        newSampledParams,...
%                                                        sampledParam_idxs);  
%                                                        
        paramDiff             = (newSampledParams - currentSampledParams);
        
        probNewGivenOld       =  log(prod(diag(chol(M_current * stepSize)))) - ...                         
                                 0.5* paramDiff * (M_invCurrent / stepSize) * paramDiff'... 
                                 -   (numSampledParams / 2)*log(2*pi); 
                             
        % The stepSize here should be what it changes to if
        % newSampledParams is accepted
        probOldGivenNew       =  log(prod(diag(chol(M_proposed * stepSize)))) - ...                         
                                 0.5* paramDiff * (M_invProposed / stepSize) * paramDiff'... 
                                 -   (numSampledParams / 2)*log(2*pi);
                                                       
        
    else 
    
         [ ~ , trajectories] = ...
                                       ...
                      ode45(...
                             equations,... 
                             timePoints,... 
                             initialValues,...   
                             odeset('RelTol', 1e-6),...                   
                             newParams...
                           );       


        % Ocassionally  trajectories may get imaginary artifacts                   
        if any(imag(trajectories(:))) 
            error('Trajectory has imaginary components');
            
        elseif hasNan(trajectories(:))
               error('Integration_Error');
        end % if

        speciesEstimates  = extractSpeciesTrajectories(trajectories,...
                                                       numStates);  
        probNewGivenOld   = 0;
        probOldGivenNew   = 0;
        
    end % if       
                                               
         
    % plot trajectories as proposed 
    if  plotProposedTrajectories
        for i = 1:numStates
            figure(i);
            hold on;
            plot(speciesEstimates(i, :));
        end % for
    end % if        
    
                            
    proposed_LL      = calculate_LL( speciesEstimates, Y,... 
                                     currentNoise,     observedStates...
                                   );                                   
    
    % Calculate the log prior for proposed parameter value   
    proposedLogPrior = zeros(1, numSampledParams);
    for p = 1: numSampledParams    
        proposedLogPrior(p) = prior(sampledParam_idxs(p),...
                                    newSampledParams(p));        
    end
    proposedLogPrior = sum(proposedLogPrior);                                                                 
                          
    
    % Calculate the log prior for current hyperparameter value
    currentLogPrior = zeros(1, numSampledParams);
    for p = 1: numSampledParams    
        currentLogPrior(p) = prior(sampledParam_idxs(p),...
                                   currentSampledParams(p));        
    end
    currentLogPrior = sum(currentLogPrior);  
        
   % Accept according to ratio of log probabilities
    ratio =... 
           beta*proposed_LL  +  proposedLogPrior +  beta*probOldGivenNew ...
         - beta*current_LL   -  currentLogPrior  -  beta*probNewGivenOld;              
        
    if isnan(ratio) ratio = -inf; end; 
    
    if ratio > 0 || log(rand) < min(0, ratio)
        % Accept proposal
        % Update variables        
        accepted                   = accepted + 1;
        
        currentParams              = newParams;
        currentSampledParams       = newSampledParams;
        current_LL                 = proposed_LL;      
        currentSpeciesEstimates    = speciesEstimates;                   
        ratioLastAccepted          = ratio;     
        currentStepSize            = stepSize;
        if mod(iterationNum, stepSizeMonitorRate) == 0             
            stepSize               = min(Model.stepMax, stepSize + ...
                                         rand*(Model.stepMax));
        end
                                    
            
    elseif mod(iterationNum, stepSizeMonitorRate + 1) == 0         
           % if iteration after stepSizeMonitorRate and proposal rejected
           stepSize = currentStepSize;
    else
        % This assumes symmetry in stepping directions          
        % Decrease stepSize by half for every order of magnitude decrease
        % in acceptance probability
        stepMax               = Model.stepMax;
        stepMin               = Model.stepMin;
        rla                   = ratioLastAccepted;       
        ratioDecadeRLA        = log(abs(rla)) / log(10);
        ratioDecade           = log(abs(ratio)) / log(10);
        changeInRatioScale    = ratioDecade - ratioDecadeRLA;
        crs                   = changeInRatioScale;
        stepSizeUpperBound    = min(stepMax, stepSize / 2^(crs));
        stepSizeLowerBound    = max(stepMin, stepSizeUpperBound);
        stepSize              = stepSizeLowerBound;
        %if (randn > 0.5) stepSign = 1; else stepSign = -1; end
        %stepSize = stepSign*stepSize;
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Display statistics and plots in Real time %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
    
    % Keep track of acceptance ratios at each iteration number
    acceptanceRatio                = 100*accepted / attempted;
    acceptanceRatios(iterationNum) = acceptanceRatio; 
    
    disp(['acceptance probability:  ' num2str(ratio) ]);    
    disp(['acceptance ratio:  '       num2str(100*accepted / attempted) ]);
    disp(['Parameters:  '             num2str(newSampledParams) ]);
    
    figStart = numStates + 1;
    figEnd   = figStart + numSampledParams;    
    plotTraces(currentSampledParams, ...
               figStart: figEnd,     ...
               iterationNum);
    
    cp = currentSampledParams;   
    paramPairs = {... 
                   [cp(1) cp(2)],... 
                   [cp(1) cp(3)],...
                   [cp(2) cp(3)] ...
                 };    
    figStart = figEnd + 1;
    figEnd   = figStart + length(paramPairs);               
    plot_2D_Slice( paramPairs, ...
                   figStart: figEnd...
                 );
    
    num3dPlots = length(Model.paramTriple_idxs);
    paramTriples = cell(1, num3dPlots);
    
    for i = 1:num3dPlots
        paramTriples{i} =   cp(Model.paramTriple_idxs{i});
    end 
    
                     
    figStart = figEnd + 1;
    figEnd   = figStart + num3dPlots;
    plot_3D_Slice( paramTriples, ...
                   figStart: figEnd...
                 );   
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Save parameters, LL, metric tensors and trajectories %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    if converged
        
        posteriorSampleNum = iterationNum -... 
                             burnin;
        
        paramHistory(posteriorSampleNum, :)        = currentSampledParams;
        LL_History(posteriorSampleNum, :)          = current_LL;  
        
        for state = 1: numStates        
            trajectoryHistory(state, posteriorSampleNum, :) = currentSpeciesEstimates(state, :);             
        end      
        
        if iterationNum == burnin + numPosteriorSamples
            % N Posterior samples have been collected so stop
            continueIterations = false;
        end
        
        disp('%%%%');
        disp(['step size: ' num2str(stepSize) ]);
        disp('%%%%');

    else        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Adjust step size based on acceptance ratio  %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%        
        
       if mod(iterationNum, stepSizeMonitorRate) == 0            
%             minAccept = stepSizeRange(1); 
%             maxAccept = stepSizeRange(2);
%             % amount to increase/decrease step size 
%             % to alter acceptance ratio 
%             dec       = 0.001; % Note: this should be based on acceptanceRatio - minAccept
%             assert(stepSize > 0);            
%             
%             if     acceptanceRatio < minAccept
%                        stepSize = stepSize  - dec;
%             elseif acceptanceRatio > maxAccept  
%                 % Steps are too small, so increase them a bit
%                        stepSize = stepSize  + dec;                         
%             end % if              
%              
%             if stepSize < .001 
%                stepSize = .001;
%             elseif stepSize > 1
%                stepSize = 1;
%             end             
%            
             disp('%%%%');
             disp(['step size: ' num2str(stepSize) ]);
             disp('%%%%');
                                 
        end % if            
        
        % Change converged tab if burn-in complete
            
        if iterationNum == burnin          
            converged  = true;    
            % End burn-in-samples timer: Get time it took to sample Burn-In
            burnInTime = toc;
            % Begin posterior samples timer: Restart timer to get time for collecting posterior samples
            tic;            
        end % if        
        
    end % if
     
end % while

% End posterior samples timer: Time to collect Posterior Samples
posteriorTime = toc;

% Save posterior
fileName = [ 'MH'...
             '_'... 
             equationName...              
           ];

save(  ['./Results/' fileName],... 
       'paramHistory',...        
       'LL_History',... 
       'burnInTime',... 
       'posteriorTime',... 
       'Y',... 
       'timePoints',...
       'acceptanceRatios',...
       'trajectoryHistory',...
       'stepSize'...
    );


end % main function


