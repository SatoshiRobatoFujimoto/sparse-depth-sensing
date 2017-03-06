function results = reconstruct_multi_frame(indices, settings)
addpath(genpath('lib'))

if nargin < 2    
    close all; clear; clc;
    settings.dataset = 'lab1';   % test_data, lids_floor6, lab1, ZED, pwlinear_nbCorners=10

    createSettings
    
    settings.solver = 'nesta';
    settings.use_slope_perspective_noDiag = false;
    settings.use_slope_perspective_diag = true;
    settings.use_slope_cartesian_noDiag = false;
    settings.subSample = 0.2;               % subsample original image, to reduce its size
    settings.percSamples = 0.01;
    settings.sampleMode = 'regular-grid';   % 'harris-feature', 'regular-grid'
    settings.doAddNeighbors = false;
    settings.stretch.flag = false;
    settings.stretch.delta_y = 0; %1e-5;
    settings.stretch.delta_z = settings.stretch.delta_y;
    
    indices = 100:5:110;
end


%% Load the lastest frame as reference
[ depth_last, rgb_last, odometry_last, depth_last_orig ] = getRawData( settings, indices(end) );  
[height, width] = size(depth_last);
N = height * width;    % total number of valid 3D points

% rgb may be not available
if isKinectDataset(settings) && sum(rgb_last(:)) == 0
    results.rgb = [];
    return
end

% convert raw data to point cloud  
if strcmp(settings.pc_frame, 'body')
    % create null odometry information
    odometry.Position.X = 0;
    odometry.Position.Y = 0;
    odometry.Theta = 0;    
end

pc_last_orig = depth2pc(depth_last_orig, rgb_last, odometry_last, settings, false);
pc_last = depth2pc(depth_last, rgb_last, odometry_last, settings, false);
pc_last_noblack = depth2pc(depth_last, rgb_last, odometry_last, settings, true);

if settings.show_figures
    fig1 = figure(1);
    
    subplot(331)
    imshow(rgb_last); title('RGB')
    drawnow
    
    subplot(332)
    pcshow(pc_last_noblack, 'MarkerSize', settings.markersize); xlabel('x'); ylabel('y'); zlabel('z'); title('Ground Truth'); 
    drawnow;
else
    fig1 = [];
end

%% Create random samples
[ samples_last, pc_samples_last] = createSamplesPointcloud( depth_last, rgb_last, odometry_last, settings );
frameID = ones(pc_samples_last.Count, 1);   % this value records which frame the points come frome

% visualization
% figure; 
% subplot(121); pcshow(pc_last); title('Latest Point Cloud'); drawnow
% subplot(122); pcshow(pc_samples_last); title('Latest Samples'); drawnow

%% generate culmulative noise
if settings.addNoise
    % use bounded noise instead of Gaussian noise
    % odom_noise = randn(length(indices)-1, 3);
    odom_noise = 2 * rand(length(indices)-1, 3) - 1;
    odom_noise = cumsum(odom_noise, 1) * settings.epsilon;
end

%% Loop over the past frames - Merge Point Clouds and Measurements
pc_truth_noblack = pc_last_noblack;
pc_truth = pc_last;
pc_samples = pc_samples_last;
count = 1;

% counting down from the latest frame, backwards in time
for i = indices(end-1 : -1 : 1) 
    % i
    [ depth_i, rgb_i, odometry_i, ~ ] = getRawData( settings, i );
    
%     if settings.addNoise
%         odometry_i.Position.X = odometry_i.Position.X + odom_noise(count, 1);
%         odometry_i.Position.Y = odometry_i.Position.Y + odom_noise(count, 2);
%         odometry_i.Position.Z = odometry_i.Position.Z + odom_noise(count, 3);
%     end
    
    pc_i = depth2pc(depth_i, rgb_i, odometry_i, settings, false);
    pc_i_noblack = depth2pc(depth_i, rgb_i, odometry_i, settings, true);
    
%     figure; 
%     subplot(121); imshow(toRangeZeroOne(depth_i))
%     subplot(122); pcshow(pc_i);drawnow
    
    % measurements
    [ samples_i, pc_samples_i] = createSamplesPointcloud( depth_i, rgb_i, odometry_i, settings );
    frameID_i = count * ones(pc_samples_i.Count, 1);   % this value records which frame the points come frome
    frameID = [frameID_i; frameID];
    count = count + 1;
    
    % merging
    pc_samples = pcmerge(pc_samples_i, pc_samples, 1e-2);  
    pc_truth = pcmerge(pc_i, pc_truth, 1e-2);  
    pc_truth_noblack = pcmerge(pc_i_noblack, pc_truth_noblack, 1e-2);  
end

% figure;
% subplot(121); pcshow(pc_truth); title('Ground Truth Cloud'); drawnow
% subplot(122); pcshow(pc_samples); title('Ground Truth Samples'); drawnow


%% Projection from a point cloud to depth and rgb images
% necessary for perspective reconstruction
[ depth_gt, rgb_gt] = pc2images( pc_truth, odometry_last, settings);
[ depth_sample, rgb_sample] = pc2images( pc_samples, odometry_last, settings);

samples = find(depth_sample > -1);
Rfull = speye(N);
sampling_matrix = Rfull(samples, :);
% measured_vector = depth_gt(samples);
measured_vector = sampling_matrix * depth_gt(:);
K = length(measured_vector);

img_sample = nan * ones(size(depth_gt));
img_sample(samples) = depth_gt(samples);

%% Naive Reconstruction
if settings.use_naive
    results.naive = reconstructDepthImage( 'naive', settings, ...
        height, width, sampling_matrix, measured_vector, samples, [], ...
        depth_gt, rgb_gt, odometry_last, pc_last_orig, fig1, 234);
end

%% Slope_Perspective_noDiag
if settings.use_slope_perspective_noDiag
    settings.useDiagonalTerm = false;
    results.slope_perspective_noDiag = reconstructDepthImage( 'slope_perspective_noDiag', settings, ...
        height, width, sampling_matrix, measured_vector, samples, results.naive.depth_rec(:), ...
        depth_gt, rgb_gt, odometry_last, pc_last_orig, fig1, 235);
end

%% Slope_Perspective_diag 
if settings.use_slope_perspective_diag
    settings.useDiagonalTerm = true;
    results.slope_perspective_diag = reconstructDepthImage( 'slope_perspective_diag', settings, ...
        height, width, sampling_matrix, measured_vector, samples, results.naive.depth_rec(:), ...
        depth_gt, rgb_gt, odometry_last, pc_last_orig, fig1, 235);
end

%% Slope_Cartesian_noDiag 
if settings.use_slope_cartesian_noDiag
    results.slope_cartesian_noDiag = reconstructDepthImage( 'slope_cartesian_noDiag', settings, ...
        height, width, sampling_matrix, measured_vector, samples, results.naive.depth_rec(:), ...
        depth_gt, rgb_gt, odometry_last, pc_last_orig, fig1, 236);
end

%% Visualization
if settings.show_figures
    figure(1);
    subplot(221); imshow(toRangeZeroOne(depth_gt)); title('Ground Truth Depth')
    subplot(222); imshow(rgb_gt); title('Ground Truth RGB')
    subplot(223); imshow(toRangeZeroOne(depth_sample)); title('Sample Depth')
    subplot(224); imshow(rgb_sample); title('Sample RGB')
    drawnow
    
    subplot(231); imshow(toRangeZeroOne(depth_last)); title('Raw Depth');
    subplot(232); imshow(img_sample); title('Samples');
    
    if settings.use_naive  
        fig=subplot(234);
        imshow(toRangeZeroOne(results.naive.depth_rec)); 
        % showColorCodedDepthImage(results.naive.depth_rec, [], fig);
        title({'Naive Perspective', ['(Error=', sprintf('%.2f', results.naive.error.euclidean), 'm)']})
    end

    if settings.use_slope_perspective_diag
        subplot(235); imshow(toRangeZeroOne(results.slope_perspective_diag.depth_rec)); 
        title({'Slope Perspective', ['(Error=', sprintf('%.2f', results.slope_perspective_diag.error.euclidean), 'm)']})
    elseif settings.use_slope_perspective_noDiag
        subplot(235); imshow(toRangeZeroOne(results.slope_perspective_noDiag.depth_rec)); 
        title({'Slope Perspective', ['(Error=', sprintf('%.2f', results.slope_perspective_noDiag.error.euclidean), 'm)']})
    end
    
    if settings.use_slope_cartesian_noDiag
        subplot(236); imshow(toRangeZeroOne(results.slope_cartesian_noDiag.depth_rec)); 
        title({'Slope Cartesian', ['(Error=', sprintf('%.2f', results.slope_cartesian_noDiag.error.euclidean), 'm)']})
    end
    drawnow
end

%% Saving results
results.pc_truth_noblack = pc_truth_noblack;
results.pc_truth = pc_truth;
% results.pc_truth_orig = pc_truth_orig;
results.pc_samples = pc_samples;
results.img_sample = img_sample;

results.rgb = rgb_gt;
results.depth = depth_gt;
results.K = K;

results.rgb_last = rgb_last;
results.depth_last = depth_last;
end