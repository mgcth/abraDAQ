function dataOut = startMultisine(hObject, eventdata, handles)

% Author: Mladen Gibanica(*)(**) and Thomas Abrahamsson(*)
% (*) Chalmers University of Technology
% Email address: mladen.gibanica@chalmers.se, thomas.abrahamsson@chalmers.se  
% Website: https://github.com/mgcth/abraDAQ
% May 2015; Last revision: 21-May-2015

% Initialaise the test setup
set(handles.startButton, 'String', 'Working!','BackGround',[1 0 0]);
multisine = startInitialisation(hObject, eventdata, handles);

% Ugly save here, but when PassXThrouFile, where X can be double, string or
% any other data type, is extended, change this
% It is deleted at the end
channelLabels = multisine.Metadata.Sensor.Label;
save([tempdir,'DataContainer00'],'channelLabels');

% Get info about channnels
CHdata = get(handles.channelsTable, 'data');
Chact = 0; for i=1:size(CHdata,1),if CHdata{i,1},Chact=Chact+1; end, end
CH = multisine.channelInfo;

% Get the sampling rate and Ts
Fs = multisine.session.Rate;
Ts = 1/Fs;

% Get frequencies and loads etc...
% [Freqs, wd, Tsd] = eval(get(handles.fun2,'String')); % should be in Hz!
Freqs = eval(get(handles.fun2,'String')); % should be in Hz!
loads = eval(get(handles.fun3,'String'));

% Correlation, between 0 and 1
CtStr=[get(handles.fun5,'String') '       '];
if strcmpi(CtStr(1:7),'default')
  Ct=.99;  
else 
  Ct = eval(get(handles.fun5,'String')); % 0.997 a good value
  if Ct>.999,Ct=.999;end
  if Ct<.8,Ct=.8;end
end

CtMeanStr=[get(handles.fun6,'String') '       '];
if strcmpi(CtMeanStr(1:7),'default')
  CtMeanInput=.95;  
else 
  CtMeanInput = eval(get(handles.fun6,'String')); % 0.95 a good value
  if CtMeanInput>.99,CtMeanInput=.99;end
  if CtMeanInput<.8,CtMeanInput=.8;end  
end

% Number of lowest frequency sinusoidal that data block should cover
NCycStr=[get(handles.fun4,'String') '       '];
if strcmpi(NCycStr(1:7),'default')
  Ncyc=10;  
else 
  Ncyc = eval(get(handles.fun4,'String')); % 10 a good value
end  
% Number of block evaluations for statistics
NStatStr=[get(handles.fun7,'String') '       '];
if strcmpi(NStatStr(1:7),'default')
  Nstat=20;  
else 
  Nstat = eval(get(handles.fun7,'String')); % 20 a good value
end

% Data that should be given or provided by multisine
refch = find(CH.active == CH.reference);
nu = length(CH.reference); % number of inputs
ny = length(CH.active); % number of outputs
yind = 1:ny; yind(refch) = [];
nf = length(Freqs);
blockSize = 16000;

% Start up parallel Matlab process that has GUI
startstr=['cmd /c start /min matlab -nosplash -nodesktop -minimize ' ...
   '-r "run(''',handles.homePath,'\functions\multisine\','simo_multisine_GUI'')"'];
dos(startstr);

% readPass = 0;
% MMF{1} = GetDoubleFromFile(1);
% while readPass == 0
%     pause(1)
%     readPass = GetDoubleFromFile(MMF{1},1);
% end

% Initiate
frdsys=frd(NaN*zeros(ny-nu,length(CH.reference),nf),2*pi*Freqs,'FrequencyUnit','rad/s');

% Obtain good number of frequencies K that can be used simulaneously
Nblock=ceil(Ncyc/Ts/min(Freqs));
K=floor(nf/10);% Start guess for number of frequency sets (not too few)
while 1,
    ind=1:K:nf;
    [~,~,~,~,A,~]=harmcoeff2(randn(nu+ny,Nblock),Ts,Freqs(ind));
    if rank(A)==min(size(A)),break;end
    K=K+1;
end

% This is the definition of stepped sine
if handles.steppedSine.Value == 1
    K=nf; % For stepped sine
end

% Pass data initially
MMF{2}=PassDoubleThruFile(2,[1 nf 1 1]); % initialise Freqs
MMF{3}=PassDoubleThruFile(3,[1 1 1 1]); % initialise ny
MMF{4}=PassDoubleThruFile(4,[1 nf/K 1 1]); % initialise indf
MMF{5}=PassDoubleThruFile(5,[1 ny-1 1 nf/K]); % initialise H real
MMF{6}=PassDoubleThruFile(6,[1 ny-1 1 nf/K]); % initialise H imag
MMF{7}=PassDoubleThruFile(7,[1 1 1 1]); % initialise C

% Pass once
PassDoubleThruFile(MMF{2},Freqs,1); % pass Freqs data
PassDoubleThruFile(MMF{3},ny,1); % pass ny data
PassDoubleThruFile(MMF{4},zeros(nf/K,1),1); % pass indf data
PassDoubleThruFile(MMF{5},zeros(ny-1,1,nf/K),1); % pass H data
PassDoubleThruFile(MMF{6},zeros(ny-1,1,nf/K),1); % pass H data
PassDoubleThruFile(MMF{7},0,1); % pass C data

% Check if any channels were added to the session
if ~isempty(multisine.session.Channels) &&  ~isempty(multisine.channelInfo.reference)
    tmpTable = get(handles.channelsTable,'Data');
    ical = {tmpTable{:,11}};
    ical = cell2mat(ical(CH.active))';
    
 
    

%%                      Give one chirp sweep to find appropriate load level    
    ucal=diag(cell2mat({tmpTable{CH.reference,11}}));
    [t,Load]=abradaq_chirp(min(Freqs),10,max(Freqs),Ts);
    qd=0.01*Load(:)/norm(Load(:),'inf');
    queueOutputData(multisine.session,qd);
    [y,times]=multisine.session.startForeground();
    u=y(:,refch)*ucal;
    MaxAmpl=max(loads);
    LoadFactor=0.01*MaxAmpl/norm(u,'inf')/norm(Load(:),'inf');
    loads=LoadFactor*loads;
    
    
    % Add listener
    LAvail=addlistener(multisine.session, 'DataAvailable', @nidaqMultisineGetDataInline);
    LReqrd=addlistener(multisine.session, 'DataRequired', @nidaqMultisinePutSineDataInline);
    LErr = addlistener(multisine.session, 'ErrorOccurred', @nidaqMultisineErrorInline);
    
    % Set up for continuous running of DAQ
    multisine.session.IsContinuous = true;
    multisine.session.NotifyWhenDataAvailableExceeds=blockSize;
    multisine.session.NotifyWhenScansQueuedBelow=ceil(blockSize/2);
    
    firstRun = true;
    
    %covH = zeros(2,2,nf);
    
    tic
    % ------------------------------------- Loop over number of frequency sets
    for I=1:K
        I
        C = 0;
        y = [];
        ynotused = [];
        iret = -1;
        opt = [];
        H0 = [];
        %H = zeros(ny-nu,1);
        
        haveData = false;
        haveReadData = true;
        haveDataContinous = false;
        firstTime = true;
        
        % Set up load
        indf=I:K:nf;
        tStart = Ts;
        blockSizeInPutData = blockSize;
        w=Freqs(indf);
        om = 2 * pi * w;
        nw=length(w);
        fi=2*pi*rand(nw,1);
        
        % Pass data
        PassDoubleThruFile(MMF{4},indf,1); % pass indf data
        
        % Collect data until after stationarity obtained
        if firstRun == true
            firstRun = false;
            nidaqMultisinePutSineDataInline(multisine.session, [])
            startBackground(multisine.session);
            pause(0.1);
        end
        
        O = 0;
        while iret == -1
            O = O + 1;
            
            pause(0.0001);
            
            % Estimate transfer functions
            if haveData == true
                ynotused = [ynotused y];
                haveReadData = true;
                haveData = false;
            end
            
            if haveDataContinous == true
                if firstTime == true
                    [iret,H,ynotused,C,opt]=simostationarityengine(ynotused,Ts,w,refch,Ncyc,Ct);
                    H0=H;
                    
                    if ~isempty(opt)
                        firstTime = false;
                    end
                    
                else
                    [iret,H,ynotused,C]=simostationarityengine(ynotused,Ts,w,refch,Ncyc,Ct,H0,opt);
                    H0=H;
                    
                end
                
                % Pass data
                %PassDoubleThruFile(MMF{4},indf,1); % pass indf data
                PassDoubleThruFile(MMF{5},real(H),1); % pass H data
                PassDoubleThruFile(MMF{6},imag(H),1); % pass H data
                PassDoubleThruFile(MMF{7},C,1); % pass C data
                pause(0.0001);
            end
            
            % Reset
            if multisine.session.IsRunning == 0
                haveDataContinous = false;
                haveData = false;
                multisine.session.stop();
                nidaqMultisinePutSineDataInline(multisine.session, [])
                disp('was 0 in stationary')
                startBackground(multisine.session);
                pause(0.1);
            end
            
        end
        
        % Obtain statistics
        Hs = zeros(size(H,1),size(H,2),size(H,3),Nstat);
        Ctmean = CtMeanInput;
        CtmeanChanged = false;
        
        for JJ=1:Nstat
            haveReadData = true;
            ynotused = [];
            haveData = false;
            haveDataContinous = false;
            
            iret = -1;
            OO = 0;
            while iret == -1
                OO = OO + 1;
                
                pause(0.0001)
                
                % Estimate transfer functions
                if haveData == true
                    ynotused = [ynotused y];
                    haveReadData = true;
                    haveData = false;
                end
                
                if haveDataContinous == true
                    [iret,H,ynotused,C]=simostationarityengine(ynotused,Ts,w,refch,Ncyc,Ctmean,H0,opt);
                    H0=H;
                    
                    if CtmeanChanged == true
                        Ctmean = CtMeanInput;
                        CtmeanChanged = false;
                    end
                end
                
                % Reset
                if multisine.session.IsRunning == 0
                    haveDataContinous = false;
                    haveData = false;
                    multisine.session.stop();
                    nidaqMultisinePutSineDataInline(multisine.session, [])
                    disp('was 0 in statistics')
                    startBackground(multisine.session);
                    pause(0.1);
                    Ctmean = Ct;
                    CtmeanChanged = true;
                end
                
            end
            Hs(:,:,:,JJ) = H;
            
            % Pass data
            PassDoubleThruFile(MMF{5},real(H),1); % pass H data
            PassDoubleThruFile(MMF{6},imag(H),1); % pass H data
            PassDoubleThruFile(MMF{7},C,1); % pass C data
            
            %for MM = 1:K
            %    covH(:,:,indf(MM)) = cov([real(H(:,:,MM)) imag(H(:,:,MM))]);
            %end
        end
        
        Hm = mean(Hs,4);
        
        % Pass data
        %PassDoubleThruFile(MMF{4},indf,1); % pass indf data
        PassDoubleThruFile(MMF{5},real(H),1); % pass H data
        PassDoubleThruFile(MMF{6},imag(H),1); % pass H data
        PassDoubleThruFile(MMF{7},C,1); % pass C data
        
        frdsys.ResponseData(:,:,indf) = Hm;
        
    end
    %PassDatagram(uh,'StopTheGUI',1);
    multisine.session.stop();
    delete(LAvail);
    delete(LReqrd);
    delete(LErr);
    %set(frdsys,'Frequency',Freqs,'Ts',Tsd);
    
    % Clean-up
    multisine.session.release();
    delete(multisine.session);
    
    timeElapsed = toc
    multisine.Metadata.TimeElapsed = timeElapsed;
    multisine.Metadata.TestDateEnd = datestr(now,'mm-dd-yyyy HH:MM:SS');
    
    % Clear DAQ
    daq.reset;
    
    % Delete the ugly temp file
    delete([tempdir,'DataContainer00']);
    
    % Covariance data too
    frdsys = idfrd(frdsys);
    
    % Calibration
    for I = 1:length(frdsys.Frequency)
        for J = 1:length(refch)
            frdsys.ResponseData(:,J,I) = diag(ical(yind)./ical(refch(J))) * frdsys.ResponseData(:,J,I);
            %frdsys.CovarianceData(I,1,J,1:2,1:2)=[covH(I,I,J) covH(I,I+ny,J); covH(I+ny,I,J) covH(I+ny,I+ny,J)];
        end
    end
    % Save data
    %Nt=dataObject.nt;
    
    % NAME THE OUTPUTS AND INPUTS, NOTE THAT IT WORKS ONLY FOR ONE INPUT...
    frdsys.InputName=multisine.Metadata.Sensor.Label(1);
    frdsys.OutputName=multisine.Metadata.Sensor.Label(2:end);
    dataOut = data2WS(2,frdsys,multisine);
   
    set(handles.startButton, 'String', 'Start measurement','BackGround',[0 1 0]);
    set(handles.statusStr, 'String', 'READY!  IDFRD and DAQ data available at workbench.');
    drawnow();
else
    errordlg('No channels or no reference.')
    set(handles.statusStr, 'String', 'Measurement aborted.');
    drawnow();
end

clear -global dataObject

    function nidaqMultisinePutSineDataInline(src, event)
        tArg = tStart:Ts:blockSizeInPutData * Ts;
        u = zeros(1,size(tArg,2));
        for II = 1:nw, u = u + loads.* sin(om(II) * tArg + fi(II)); end
        src.queueOutputData(u(:));
        blockSizeInPutData = blockSizeInPutData + blockSize;
        tStart = tArg(end) + Ts;
    end

    function nidaqMultisineGetDataInline(src, event)
        %t=event.TimeStamps;
        if haveReadData == true
            y=event.Data.';
        else
            y = [y event.Data'];
        end
        
        haveData = true;
        haveReadData = false;
        
        haveDataContinous = true;
    end

end