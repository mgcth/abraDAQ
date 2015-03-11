function dataOut = startMultisine(hObject, eventdata, handles)

global dataObject HFRFGUI CH

% Initialaise the test setup
steppedSine = startInitialisation(hObject, eventdata, handles);

% Get info about channnels
CHdata = get(handles.channelsTable, 'data');
Chact=0;for i=1:size(CHdata,1),if CHdata{i,1},Chact=Chact+1;end,end
CH = steppedSine.channelInfo;

% Check if any channels was added to the session
if ~isempty(steppedSine.session.Channels) &&  ~isempty(steppedSine.channelInfo.reference)
    % Add listener
    steppedSine.eventListener = addlistener(steppedSine.session, 'DataAvailable', @(src, event) logDataTA(src, event));
    
    % Start steppedSine
    %steppedSine.session.startForeground();
    
    % Actual steppedSine test                             Initiate and test
    Fs=steppedSine.session.Rate;Ts=1/Fs;
    
    Freqs = eval(char(get(handles.fun2,'String')));
    Loads = eval(char(get(handles.fun3,'String')));
    
    % NCyclesInBlock=8;%                    Minimum number of periods in AI block
    % NBlocks=4;%                           Number of blocks in AO buffer
    HarmOrder=2;
    Ny=length(steppedSine.channelInfo.active);Nf=length(Freqs);
    
    if length(Loads==1),Loads=Loads*ones(size(Freqs));end
    
    rampcycles=5;
    skipcycles=50;
    takecycles=20;
    % Naverages=20;
    tmargin=0.2;%Margin to compensate for the modules trigger att different times
    
    % Fs=steppedSine.session .Rate;Ts=1/Fs;
    % AIBSmin=ceil(Fs/10);
    
    %                                                          Initiate GUI
    frf_gui;
    Refch = find(steppedSine.channelInfo.active == steppedSine.channelInfo.reference);
    tmpTable = get(handles.channelsTable,'Data');
    cal = 1./[tmpTable{steppedSine.channelInfo.active,10}];
    ical = 1./cal;
    names = steppedSine.channelInfo.active;
    
    times = [];
    Data = [];
    h=figure;
    
    for I=1:Nf
        f=Freqs(I);
        
        Rate=50*f;if Rate<1000,Rate=1000;end
        if Rate>51200;Rate=51200;end
        steppedSine.session.Rate=Rate;
        Fs=Rate;Ts=1/Fs;
        Nramp=rampcycles/f/Ts;
        w=(1-cos(pi*[0:Nramp-1]/Nramp))/2;
        t=0:Ts:(skipcycles+takecycles)/f+tmargin;
        
        Nskip=length(0:Ts:skipcycles/f);
        Nskipandtake=length(0:Ts:(skipcycles+takecycles)/f);
        
        W=ones(length(t),1);W(1:length(w))=w;
        Sine=Loads(I)*W.*sin(2*pi*f*t(:));
        
        %steppedSine = addlistener(steppedSine.session, 'DataAvailable', @(scr, event) tempSine(src, event));
        queueOutputData(steppedSine.session,Sine);
        [Data,times,Trigt]=steppedSine.session.startForeground();
        %startBackground(steppedSine.session);
        %wait
        stop(steppedSine.session);% This terminates activities that may interfere
        
        figure(h);
        plot(times,Data(:,3-1));
        
        tuse=times(Nskip+1:Nskipandtake);
        Datause=Data(Nskip+1:Nskipandtake,:);
        
        [c,RN(:,I),RH(:,I),RS(:,I),C,PW(:,I)] = ...
            harmonics(Datause,Ts,f,HarmOrder,Refch);
        
        Yc=diag(ical)*C./repmat(ical(Refch)*C(Refch,:),size(C,1),1);
        meanY(:,I)=mean(Yc,2);
        if any(isnan(meanY)),keyboard,end
        covY(:,:,I)=cov([real(Yc.') imag(Yc.')]);
        stdY(:,I)=sqrt(diag(covY(1:Ny,1:Ny)).^2+ ...
            diag(covY(Ny+1:2*Ny,Ny+1:2*Ny)).^2);
        %
        ycal=Datause*diag(ical);
        frf_gui(tuse-tuse(1),ycal,I,Freqs,meanY,stdY,RN,RH,RS,PW,names);
        
    end
    
    % temporary
    close(HFRFGUI.hFigtd, HFRFGUI.hFigdd, HFRFGUI.hFigfd, HFRFGUI.Fig, h);
    
    % Make IDFRD data object
    for I=1:Ny
        for J=1:Nf
            idCovY(I,1,J,1:2,1:2)=[covY(I,I,J) covY(I,I+Ny,J);covY(I+Ny,I,J) covY(I+Ny,I+Ny,J)];
        end
    end
    ind=find(steppedSine.channelInfo.active==steppedSine.channelInfo.reference);
    meanY(ind,:)=[];idCovY(ind,:,:,:,:)=[];% Exclude reference
    
    frdsys=frd(reshape(meanY,size(meanY,1),1,size(meanY,2)),2*pi*Freqs,'FrequencyUnit','rad/s');
    frdsys=idfrd(frdsys);
    frdsys.CovarianceData=idCovY;
    
    % Clean-up
    steppedSine.session.release();
    delete(steppedSine.session);
    
    % Clear DAQ
    daq.reset;
    
    % Save data
    Nt=dataObject.nt;
    dataOut = data2WS(2,dataObject.t(1:Nt),dataObject.data(1:Nt,:),frdsys,multisine);
    
    set(handles.statusStr, 'String', 'READY!  IDFRD and DAQ data available at workbench.');
    drawnow();
else
    errordlg('No channels or no reference.')
    set(handles.statusStr, 'String', 'Measurement aborted.');
    drawnow();
end

clear('dataObject');

    function tempSine(src, event)
        d = event.Data;
        tt = event.TimeStamps;
        
        Data = [d; Data];
        times = [tt; times];
        
    end
end