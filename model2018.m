function output=model2018(sign,fs,fc,irregularities,storeflag,subject,sheraPo,IrrPct,non_linear_type,nH,nM,nL,clean,data_folder)
% function output=model2018(sign,fs,fc,irregularities,storeflag,subject,sheraPo,IrrPct,non_linear_type,nH,nM,nL,clean,data_folder)
%
% Computational model of the auditory periphery (Verhulst, Altoe, Vasilkov, 2018).
%
% Input:
%   -sign: stimulus
%   -fs: samplerate
%   -fc: probe frequency or alternatively a string 'all' to probe all cochlear
%        sections or 'half' to probe half sections, 'abr' to store the
%        401 sections used to compute the abr responses in Verhulst et al. 2017
%   -irregularities: decide wether turn on (1) or off (0) irregularities and
%        nonlinearities of the cochlear model (default 1 )
%   -storeflag: string that sets what variables to store from the computation, 
%        each letter correspond to one desired output variable (e.g., 'avhl' 
%        to store acceleration, displacement, high and low spont. rate fibers.) 
%        See "output" for the corresponding characters. Default: 'avihmlebw'.
%   -subject: number representing the seed to generate the random
%        irregularities in the cochlear sections (default 1)
%   -sheraPo: starting real part of the poles of the cochlear model
%        it can be either an array with one value per BM section,  or a
%        single value far all section (default 0.6)
%   -IrrPct: magnitude of random perturbations on the BM (irregularities, default 0.05=5%)
%   -non_linear_type: select the type of nonlinearity in the BM model.
%        Currently implemented
%           'vel'= instantaneouns nonlinearity based on local BM velocity (see Verhulst et al. 2012)
%           'none'= linear model
%   -nH,nM,nL= number of high, medium and low spont. fibers employed to
%        compute the response of cn and ic nuclei. Default 13,3,3. This
%        parameters can be passed either as a single value for all sections or
%        as an array with each value corresponding to a single CF location (and
%        the length of those array must match the number of the section probed)
%
%  Output:
%   -output.v: BM velocity     (store 'v')
%   -output.y: BM displacement (store 'y')
%   -output.emission: pressure output from the middle ear (store 'e')
%   -output.cf: center frequencies (always stored)
%   -output.ihc: IHC receptor potential (store 'i')
%   -output.anfH: HSR fiber spike probability [0,1] (store 'h')
%   -output.anfM: MSR fiber spike probability [0,1] (store 'm')
%   -output.anfL: LSR fiber spike probability [0,1] (store 'l')
%   -output.an_sum: summation of HSR, MSR and LSR per channel,i.e., the input to the cn model  (storeflag 'b')
%   -output.cn: cochlear nuclei output (storeflag 'b')
%   -output.ic: IC (storeflag 'b')
%   -output.w1,outupt.w3,output.w5: wave 1,3 and 5 (storeflag 'w')
%   -output.fs_bm= sampling frequency of the bm simulations
%   -output.fs_ihc= sample rate of the inner hair cell output
%   -output.fs_an= sample rate of the an output
%   -output.fs_abr= sample rate of the IC,CN and W1/3/5 outputs
%   -clean: delete the temporary files generated by the python call (1) or
%            not (0). Default 1
%   -data_folder: string of folder where to save the temporary files
%               generated by the python call (default current folder)
%
% References:
%       Verhulst, S., Altoe, A., and Vasilkov, V. (2018). Computational 
%           modeling of the human auditory periphery: Auditorynerve responses, 
%           evoked potentials and hearing loss. Hearing Research, vol. 360, pp. 55-75.
%
%       See also:
%       Verhulst, S., Ernst, F., Garrett, M. and Vasilkov, V. (2018). 
%           Suprathreshold psychoacoustics and envelope-following response 
%           relations: Normal-hearing, synaptopathy and cochlear gain loss. 
%           Acta Acustica united with Acustica, vol. 104, pp. 800-803.
%
% -------------------------------------------------------------------------
% The model code and interface was written by Alessandro Altoe and Sarah 
% Verhulst (copyright 2012,2014,2015,2016,2018) and is licensed under the 
% UGent acadamic license (see details in license file that is part of this 
% repository). 
% The Verhulstetal2018Model consists of the following files: 
%       tridiag.so, cochlea_utils.c, run_model2018.py, model2018.m, 
%       cochlear_model2018.py, inner_hair_cell2018.py, auditory_nerve2017.py, 
%       ic_cn2017.py, ExampleSimulation.m, ExampleAnalysis.m, and the 
%       HI profiles in the Poles folder.
% -------------------------------------------------------------------------

DECIMATION=5;
[channels,idx]=min(size(sign));
if nargin<13
    data_folder=[pwd(),'/'];
end
if nargin<13
    clean=1;
end
if nargin < 12
    nL=3;
end
if nargin < 11
    nM = 3;
end
if nargin < 10
    nH = 13;
end
if nargin < 9
    non_linear_type = 'vel';
end
if nargin < 8
    IrrPct = 0.05;
end
if nargin < 7
    sheraPo = 0.06;
end
if nargin < 6
    subject = 1;
end
if nargin < 5
    storeflag = 'vihlmeb';
end
if nargin< 4
    irregularities=ones(1,channels);
end

if clean == 1
    fname2clean = []; %%% AO
end

if(numel(irregularities)==1)
    irregularities=irregularities*ones(1,channels);
end

Fs=fs;
sectionsNo=1e3;
[channels,idx]=min(size(sign));
if(idx==2) %transpose it (python C-style row major order)
    sign=sign';
end
stim=sign;

if(isstr(fc) && strcmp(fc,'all')) %if probing all sections 1001 output (1000 sections plus the middle ear)
    l=sectionsNo;
elseif(isstr(fc) && strcmp(fc,'half')) %if probing half sections sections 1001 output (1000 sections plus the middle ear)
    l=sectionsNo/2;
elseif(isstr(fc) && strcmp(fc,'abr')) %if probing half sections sections 1001 output (1000 sections plus the middle ear)
    l=401;
else %else pass it as a column vector
    [l,idx]=max(size(fc));
    if(idx==2)
        fc=fc'; 
    end
    fc=round(fc);
end
probes=fc;

act_path=pwd;

%%% Storing input.mat which will be read 'later' in Python
fname = 'input.mat';
save(fname,'stim','Fs','channels','subject','sheraPo','irregularities','probes',...
    'sectionsNo','data_folder','storeflag','IrrPct','non_linear_type','nH','nM','nL','-v7');

%%% Running the model
[status,res] = system('python run_model2018.py','-echo');

switch status
    case 0 %%% If the simulation succeeded then the stored results are read
        cd(data_folder);

        for i=1:channels

            p=length(stim(i,:));
            p2=ceil(length(stim(i,:))/DECIMATION);

            fname = strcat('cf',int2str(i),'.mat');
            tmp = load(fname,'cf');
            output(i).cf = tmp.cf;
            if clean; fname2clean{end+1} = fname; end

            if strfind(storeflag,'v')
                fname = strcat('v',int2str(i),'.mat');
                tmp = load(fname,'Vsolution');
                output(i).v = tmp.Vsolution;
                if clean; fname2clean{end+1} = fname; end
            end

            if strfind(storeflag,'y')
                fname = strcat('y',int2str(i),'.mat');
                tmp = load(fname,'Ysolution');
                output(i).y = tmp.Ysolution;
                if clean; fname2clean{end+1} = fname; end
            end

            if strfind(storeflag,'e')
                fname = strcat('emission',int2str(i),'.mat');
                tmp = load(fname,'oto_emission');
                output(i).e = tmp.oto_emission;
                if clean; fname2clean{end+1} = fname; end
            end

            if strfind(storeflag,'i')
                fname = strcat('ihc',int2str(i),'.mat');
                tmp = load(fname,'Vm');
                output(i).ihc = tmp.Vm;
                if clean; fname2clean{end+1} = fname; end
            end

            if strfind(storeflag,'h')
                fname = strcat('anfH',int2str(i),'.mat');
                tmp = load(fname,'anfH');
                output(i).anfH = tmp.anfH;
                if clean; fname2clean{end+1} = fname; end
            end

            if strfind(storeflag,'m')
                fname = strcat('anfM',int2str(i),'.mat');
                tmp = load(fname,'anfM');
                output(i).anfM = tmp.anfM;
                if clean; fname2clean{end+1} = fname; end
            end

            if strfind(storeflag,'l')
                fname = strcat('anfL',int2str(i),'.mat');
                tmp = load(fname,'anfL');
                output(i).anfL = tmp.anfL;
                if clean; fname2clean{end+1} = fname; end
            end

            if strfind(storeflag,'b')
                fname = strcat('cn',int2str(i),'.mat');
                tmp = load(fname,'cn');
                output(i).cn = tmp.cn;
                if clean; fname2clean{end+1} = fname; end

                fname = strcat('ic',int2str(i),'.mat');
                tmp = load(fname,'ic');
                output(i).ic = tmp.ic;
                if clean; fname2clean{end+1} = fname; end

                fname = strcat('AN',int2str(i),'.mat');
                tmp = load(fname,'anSummed');
                output(i).an_summed = tmp.anSummed;
                if clean; fname2clean{end+1} = fname; end
            end

            if strfind(storeflag,'w')
                fname = strcat('1w',int2str(i),'.mat');
                tmp = load(fname,'w1');
                output(i).w1 = tmp.w1;
                if clean; fname2clean{end+1} = fname; end

                fname = strcat('3w',int2str(i),'.mat');
                tmp = load(fname,'w3');
                output(i).w3 = tmp.w3;
                if clean; fname2clean{end+1} = fname; end %%% AO

                fname = strcat('5w',int2str(i),'.mat');
                tmp = load(fname,'w5');
                output(i).w5 = tmp.w5;
                if clean; fname2clean{end+1} = fname; end %%% AO
            end

            output(i).fs_abr=fs/DECIMATION;
            output(i).fs_an=fs/DECIMATION;
            output(i).fs_bm=fs;
            output(i).fs_ihc=fs;
        end

        if clean==1
            for i = 1:length(fname2clean)
                try
                    delete(fname2clean{i});
                end
            end    
            % delete *.mat
        end
        
        cd(act_path);
    
    otherwise %%% Then the simulation did not succeed
     
        disp(res) % it re-prints the Python warning...
        error('Something went wrong (see the Python warning)')
end
