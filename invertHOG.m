% invertHOG(feat)
%
% This function recovers the natural image that may have generated the HOG
% feature 'feat'. Usage is simple:
%
%   >> feat = features(im, 8);
%   >> ihog = invertHOG(feat);
%   >> imagesc(ihog); axis image;
%
% By default, invertHOG() will load a prelearned paired dictionary to perform
% the inversion. However, if you want to pass your own, you can specify the
% optional second parameter to use your own parameters:
% 
%   >> pd = learnpairdict('/path/to/images');
%   >> ihog = invertHOG(feat, pd);
%
% This function should take no longer than a second to invert any reasonably sized
% HOG feature point on a 12 core machine.
function im = invertHOG(feat, pd),

if ~exist('pd', 'var'),
  global ihog_pd
  if isempty(ihog_pd),
    if ~exist('pd-color.mat', 'file'),
      fprintf('ihog: notice: unable to find paired dictionary\n');
      fprintf('ihog: notice: attempting to download in 3');
      pause(1); fprintf(', 2'); pause(1); fprintf(', 1'); pause(1);
      fprintf(', now\n');
      urlwrite('http://people.csail.mit.edu/vondrick/pd-color.mat', 'pd-color.mat');
      fprintf('ihog: notice: download complete\n');
    end
    ihog_pd = load('pd-color.mat');
  end
  pd = ihog_pd;
end

par = 5;
feat = padarray(feat, [par par 0], 0);

[ny, nx, ~] = size(feat);

% pad feat with 0s if not big enough
if size(feat,1) < pd.ny,
  x = padarray(x, [pd.ny - size(x,1) 0 0], 0, 'post');
end
if size(feat,2) < pd.nx,
  x = padarray(x, [0 pd.nx - size(x,2) 0], 0, 'post');
end

% pad feat if dim lacks occlusion feature
if size(feat,3) == features-1,
  feat(:, :, end+1) = 0;
end

% extract every window 
windows = zeros(pd.ny*pd.nx*features, (ny-pd.ny+1)*(nx-pd.nx+1));
c = 1;
for i=1:size(feat,1) - pd.ny + 1,
  for j=1:size(feat,2) - pd.nx + 1,
    hog = feat(i:i+pd.ny-1, j:j+pd.nx-1, :);
    hog = hog(:) - mean(hog(:));
    hog = hog(:) / sqrt(sum(hog(:).^2) + 1);
    windows(:,c)  = hog(:);
    c = c + 1;
  end
end

% solve lasso problem
param.lambda = pd.lambda;
param.mode = 2;
a = full(mexOMP(single(windows), pd.dhog, param));
recon = pd.dgray * a;

% reconstruct
im      = zeros((size(feat,1)+2)*pd.sbin, (size(feat,2)+2)*pd.sbin, 3);
weights = zeros((size(feat,1)+2)*pd.sbin, (size(feat,2)+2)*pd.sbin);
c = 1;
for i=1:size(feat,1) - pd.ny + 1,
  for j=1:size(feat,2) - pd.nx + 1,
    fil = fspecial('gaussian', [(pd.ny+2)*pd.sbin (pd.nx+2)*pd.sbin], 9);
    patch = reshape(recon(:, c), [(pd.ny+2)*pd.sbin (pd.nx+2)*pd.sbin 3]);
    patch(:, :, 1) = patch(:, :, 1) .* fil;
    patch(:, :, 2) = patch(:, :, 2) .* fil;
    patch(:, :, 3) = patch(:, :, 3) .* fil;

    iii = (i-1)*pd.sbin+1:(i-1)*pd.sbin+(pd.ny+2)*pd.sbin;
    jjj = (j-1)*pd.sbin+1:(j-1)*pd.sbin+(pd.nx+2)*pd.sbin;

    im(iii, jjj, :) = im(iii, jjj, :) + patch;
    weights(iii, jjj) = weights(iii, jjj) + 1;

    c = c + 1;
  end
end

% post processing averaging and clipping
im(:, :, 1) = im(:, :, 1) ./ weights;
im(:, :, 2) = im(:, :, 2) ./ weights;
im(:, :, 3) = im(:, :, 3) ./ weights;
im = im(1:(ny+2)*pd.sbin, 1:(nx+2)*pd.sbin, :);

r = im(:, :, 1);
r(:) = r(:) - min(r(:));
r(:) = r(:) / max(r(:));

g = im(:, :, 2);
g(:) = g(:) - min(g(:));
g(:) = g(:) / max(g(:));

b = im(:, :, 3);
b(:) = b(:) - min(b(:));
b(:) = b(:) / max(b(:));

im = cat(3, r, g, b);

im = im(par*pd.sbin:end-par*pd.sbin, par*pd.sbin:end-par*pd.sbin, :);
