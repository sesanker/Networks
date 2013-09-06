% Returns true if matrix has any NaN entries
% Usefull for checks trajectory matricies for NaN
% Values
function  isTrue = hasNaN(matrix)
isTrue = any(isnan(matrix(:)));
end
