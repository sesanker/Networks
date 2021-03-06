function priorProb = gammaPrior(paramNum, param)

%%%%%%%%%
% log Gamma %
%%%%%%%%%

if (param < 0)
   priorProb = - Inf;
else
% Calculate probability of value from the prior
if paramNum == 9
   priorProb = log(gampdf(param, 1, sqrt(24)));
else    
   priorProb = 0;
end
      
        
end

