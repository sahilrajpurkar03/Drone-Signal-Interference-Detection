import matlab.net.*
import matlab.net.http.*

% Server address and parameters
address = 'http://localhost:54664/';
endpoint = 'sample';  % Endpoint to fetch spectral data
numFrames = 200;  % Number of frames to display in the waterfall
pauseTime = 0.5;  % Time (in seconds) between data fetches

% Frequency range
x = linspace(2.3982e+09, 2.4857e+09, 448);  % Frequency range (Hz)

% Waterfall setup
figure('Position', [100, 100, 1200, 600]);

% Subplot 1: Spectrum plot
subplot(2, 1, 1);
spectrumPlot = plot(x, nan(1, 448), 'LineWidth', 1.5);
hold on;
peakMarkers = scatter(nan, nan, 50, 'r', 'filled');  % Peak markers
xlabel('Frequency (Hz)');
ylabel('Power (dBm)');
title('Live Spectrum with Peak Detection');
grid on;

% Subplot 2: Waterfall plot
subplot(2, 1, 2);
hold on;
waterfallData = nan(numFrames, 448);  % Initialize waterfall matrix
y = 1:numFrames;  % Time index for waterfall
waterfallPlot = surf(x, y, waterfallData, 'EdgeColor', 'none');
xlabel('Frequency (Hz)');
ylabel('Time Frame');
zlabel('Power (dBm)');
title('Live Waterfall Spectrum');
view(2);  % Set to 2D view for heatmap-style display
colorbar;
caxis([-110 0]);  % Adjust color axis based on power range

% Initialize storage for all samples
allSamples = nan(numFrames, 448);

% Live update loop
try
    for frame = 1:numFrames
        % Fetch data from the server
        r = RequestMessage;
        resp = send(r, URI(append(address, endpoint)));
        
        % Check response status
        if resp.StatusCode == matlab.net.http.StatusCode.OK
            % Extract power samples
            samples = resp.Body.Data.samples;  % Update if field name differs
            waterfallData(frame, :) = samples;  % Add to waterfall matrix
            allSamples(frame, :) = samples;    % Store for post-processing
            
            % Update spectrum plot
            set(spectrumPlot, 'YData', samples);
            
            % Detect peaks
            [peakValues, peakLocs] = findpeaks(samples, x, ...
                'MinPeakHeight', -90, ...         % Minimum peak height
                'MinPeakProminence', 3, ...      % Minimum prominence
                'MinPeakDistance', 5e6);         % Minimum distance between peaks
            
            % Update peak markers
            set(peakMarkers, 'XData', peakLocs, 'YData', peakValues);
            
            % Update waterfall plot
            set(waterfallPlot, 'ZData', waterfallData);
            drawnow;  % Force MATLAB to update the plots
            
            % Shift old data for continuous display
            if frame == numFrames
                waterfallData(1:end-1, :) = waterfallData(2:end, :);
                frame = numFrames - 1;  % Keep loop index in range
            end
        else
            warning('Failed to fetch data. Status: %s', char(resp.StatusCode));
        end
        
        pause(pauseTime);  % Wait before fetching the next frame
    end
    
    % Post-processing after 200 frames
    avgSpectrum = mean(allSamples, 1);  % Average spectrum over all frames
    
    % Detect OFDM (15 MHz wide) and Bluetooth (2 MHz wide) channels
    [peakValues, peakLocs, widths, prominences] = findpeaks(avgSpectrum, x, ...
        'MinPeakHeight', -90, ...
        'MinPeakProminence', 5, ...
        'Annotate', 'extents');
    
    fprintf('Detected Channels:\n');
    for i = 1:length(peakLocs)
        channelWidth = widths(i);
        if channelWidth >= 15e6
            fprintf('OFDM channel approx %.2f MHz detected at %.3f GHz\n', ...
                channelWidth / 1e6, peakLocs(i) / 1e9);
        elseif channelWidth >= 2e6 && channelWidth < 15e6
            fprintf('Bluetooth channel approx %.2f MHz detected at %.3f GHz\n', ...
                channelWidth / 1e6, peakLocs(i) / 1e9);
        else
            fprintf('Narrowband signal detected: %.2f MHz at %.3f GHz\n', ...
                channelWidth / 1e6, peakLocs(i) / 1e9);
        end
    end
catch ME
    warning('Error during live update: %s', ME.message);
end
