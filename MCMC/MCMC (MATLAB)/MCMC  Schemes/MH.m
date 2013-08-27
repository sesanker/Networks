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
initialValues                      = Model.initialValues;

stepSize                           = Model.initialStepSize;  
stepSizeRange                      = Model.stepSizeRange; 

burnin                             = Model.burnin;
numPosteriorSamples                = Model.numPosteriorSamples;
equationName                       = Model.equationName;
totalParams                        = Model.totalParams;
timePoints                         = Model.timeData;
plotProposedTrajectories           = Model.plotProposedTrajectories;

sampledParam_idxs                  = Model.sampledParam_idxs;
                                     
M                                  = Model.preConditionMatrix;


% Model specific priors:
% Prior struct of priors and derivatives
% Objective priors throw exceptions when parameters reach
% regions of zero probability
Prior                   = Model.Prior;

% Used in calculating prior probabilities of current and proposed parameters
prior                   = Prior.prior;
                          
sampledParams           = totalParams(sampledParam_idxs);


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

% Default step size is: 1 /  (number of covariates) ^ (- 1/3)
if strcmp(stepSize, 'default')
    stepSize = numSampledParams^(- 1/3);
end  


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Calculate  maximum likelihood values of parameters                      %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%                    

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
paramHistory        = zeros(numPosteriorSamples, numTotalParams);
LL_History          = zeros(numPosteriorSamples, numStates);
trajectoryHistory   = cell(1, numPosteriorSamples);

% Set monitor rate for adapting step sizes
stepSizeMonitorRate = 10;

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
    
    iterationNum = iterationNum + 1;     
    
    attempted    = attempted    + 1; 
    
    disp(['Iteration:  '...
          num2str(iterationNum)]);
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Update parameters       %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%  
    
    
    newSampledParams      = randn(1, numSampledParams) * stepSize * M; 
    
    newParams             = updateTotalParameters( totalParams,...
                                                   newSampledParams,...
                                                   sampledParam_idxs);   
    
    totalMean             = updateTotalParameters( totalParams,...
                                                   mean,...
                                                   sampledParam_idxs);  
    %%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Integrate Equations     %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%    
             
     [ ~ , trajectories] = ...
                                  ...
                  ode45(...
                         equations,... 
                         timePoints,... 
                         initialValues,...   
                         odeset('RelTol', 1e-6),...                   
                         totalParameters...
                       );  
                   
   
    
                   % Ocassionally  trajectories may get imaginary artifacts                   
    if any(imag(trajectories(:)))
        error('Trajectory has imaginary components');
    end % if
        
    speciesEstimates  = extractSpeciesTrajectories(trajectories,...
                                                   numStates);
                                   
         
    % plot trajectories as proposed 
    if  plotProposedTrajectories
        for i = 1:numStates
            figure(i);
            hold on;
            plot(speciesEstimates(i, :));
        end % for
    end % if
    
    % Calculate probability of proposed parameters given current parameters
    % The first term is the log of the normalization constant
    probNewGivenOld   = - log(prod(diag(chol(invG * stepSize^2)))) - ...
                          0.5*(mean - newSampledParams) * (M / stepSize^2) * (mean - newSampledParams)'... 
                          -   (numSampledParams / 2)*log(2*pi);   
    try
        gradient_LL = LL_Gradient(...
                                   newSampledParams,   sensitivities_1,... 
                                   numSampledParams,   observedStates,... 
                                   numTimePts,         speciesEstimates,... 
                                   Y,                  currentNoise,...
                                   priorDerivative...
                                 );
    catch    
        iterationNum = iterationNum - 1;    
        attempted    = attempted    - 1;  
        % redo current iteration step        
        continue
    end % try                                                                                                     
                                  
    if Model.isMala 
        G           = eye(numSampledParams);
        invG        = G;
        firstTerm   = gradient_LL;  
        secondTerm  = zeros(1, numSampledParams);
        thirdTerm   = zeros(1, numSampledParams);    
    elseif  calculateTensor
        G           = metricTensor(...
                                   newSampledParams,   sensitivities_1,... 
                                   numSampledParams,   observedStates,... 
                                   currentNoise,       priorSecondDerivative...                              
                                  );

        identity    = eye(numSampledParams); 
        % In addition to bounding singular values
        % add diagonal dust to improve rank                                       
        invG        =  identity / (G + identity*1e-6);
        firstTerm   = (invG * gradient_LL')';  

        if zeroMetricTensorDerivatives

         secondTerm =  zeros(1, numSampledParams);
         thirdTerm  =  zeros(1, numSampledParams);

        else     
            GDeriv = ...
                     metricTensorDeriviatives...
                      (... 
                        sensitivities_1,   observedStates,  ...
                        sensitivities_2,   numSampledParams, ...
                        currentNoise,      newSampledParams, ...
                        priorThirdDerivative...
                      );  

         [secondTerm, ...
          thirdTerm] = secondAndThirdTerms(invG, GDeriv,...
                                           numSampledParams);
        end % if  
        
    else % Everything is recalculated using the same G and its derivatives here
        firstTerm   = (invG * gradient_LL')'; 
    
    end % if
        
    mean  = newSampledParams     + (stepSize^2 / 2) * firstTerm  ...
                                 -  stepSize^2      * secondTerm ...
                                 + (stepSize^2 / 2) * thirdTerm;
                          
    totalMean             = updateTotalParameters( totalParams,...
                                                   mean,...
                                                   sampledParam_idxs);                      
     
    % Calculate probability of current parameters given proposed parameters   
    % The first term is the log of the normalization constant 
    % log(prod(diag(chol... is a fast calculation of log determinant                
    probOldGivenNew  = - log(prod(diag(chol(invG * stepSize^2)))) - ...                         
                         0.5*(mean - currentSampledParams) * (G / stepSize^2) * (mean - currentSampledParams)'... 
                         -   (numSampledParams / 2)*log(2*pi); 
                         
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
                 proposed_LL  +  proposedLogPrior  +  probOldGivenNew -... 
                 current_LL   -  currentLogPrior   -  probNewGivenOld;           
      
        
    if ratio > 0 || log(rand) < min(0, ratio)
        % Accept proposal
        % Update variables        
        accepted                   = accepted + 1;
        
        currentParams              = newParams;
        currentSampledParams       = newSampledParams;
        current_LL                 = proposed_LL;            
        currentG                   = G;
        currentInvG                = invG;            
        currentFirstTerm           = firstTerm;
        currentSecondTerm          = secondTerm;
        currentThirdTerm           = thirdTerm;  
        currentSpeciesEstimates    = speciesEstimates;
                   
    end
    
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
    
    paramTriples = {... 
                     [cp(1) cp(2) cp(3)],...                      
                   }; 
                     
    figStart = figEnd + 1;
    figEnd   = figStart + length(paramTriples);
    plot_3D_Slice( paramTriples, ...
                   figStart: figEnd...
                 );   
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Save parameters, LL, metric tensors and trajectories %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    if converged
        
        posteriorSampleNum = iterationNum -... 
                             burnin;
        
        paramHistory(posteriorSampleNum, :)        = currentParams;
        LL_History(posteriorSampleNum, :)          = current_LL;        
        metricTensorHistory{posteriorSampleNum}    = currentG;
        trajectoryHistory{posteriorSampleNum}      = currentSpeciesEstimates;        
        
        if iterationNum == burnin + numPosteriorSamples
            % N Posterior samples have been collected so stop
            continueIterations = false;
        end     
        

    else        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Adjust step size based on acceptance ratio  %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%        
        
       if mod(iterationNum, stepSizeMonitorRate) == 0            
            minAccept = stepSizeRange(1); 
            maxAccept = stepSizeRange(2);
            % amount to increase/decrease step size 
            % to alter acceptance ratio 
            dec       = 0.05; % Note: this should be based on acceptanceRatio - minAccept
            assert(stepSize > 0);            
            
            if     acceptanceRatio < minAccept
                       stepSize = stepSize  - dec;
            elseif acceptanceRatio > maxAccept  
                % Steps are too small, so increase them a bit
                       stepSize = stepSize  + dec;                         
            end % if   
            
             if Model.isMala
                if stepSize < .05 
                   stepSize = .05;
                elseif stepSize > 1
                    stepSize = 1;
                end
             else                
                if stepSize < .6 
                   stepSize = .6;
                elseif stepSize > 1.5
                    stepSize = 1.5;
                end
             end % if
            
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
fileName = [ 'mMALA'...
             '_'... 
             equationName...              
           ];

save(  ['./Results/' fileName],... 
       'paramHistory',... 
       'metricTensorHistory',... 
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


