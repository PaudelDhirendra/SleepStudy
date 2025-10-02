SleepStudy
================

#### Overview
SleepStudy is a fork of [SpectralTrainFig](https://github.com/nsrr/SpectralTrainFig) repo. The original readme from SpectralTrainFig is available [here](https://github.com/PaudelDhirendra/SleepStudy/blob/master/README_SpectralTrainFig.md). SleepStudy is a graphical user interface that allows a user to select a folder of [EDF](http://en.wikipedia.org/wiki/European_Data_Format)/[XML](https://en.wikipedia.org/wiki/XML) files to apply [Spectral Analysis](http://en.wikipedia.org/wiki/Spectral_estimation), [Coherence Analysis](https://en.wikipedia.org/wiki/Coherence_(signal_processing)) and [Sleep Cycle Analysis](https://en.wikipedia.org/wiki/Sleep_cycle) to [electroencephlography signals (EEG)](http://en.wikipedia.org/wiki/Electroencephalography). The program includes a spectral threshold artifact detection scheme described in the [literature](http://www.ncbi.nlm.nih.gov/pubmed/16388912). And a template-subtraction based ECG artifact removal algorithm. SpectralTrainFig is a user friendly approach to the SpectralAnalysisClass function. The GUI versions allows a user to perform spectral or coherence analysis without having to do any programming. EXCEL and PowerPoint summaries are configured by user defined settings and specified spectral bands. Detail epoch by epoch and subject summaries are provided for both NREM and REM states. Additional details are described below. 
#### Required MATLAB Toolbox
   1. Signal Processing Toolbox.
   2. Statistics and Machine Learning Toolbox.
   3. Curve Fitting Toolbox (This is required for ECG decontamination usage).
#### Getting Started
The steps involved in setting up spectral analysis, Sleep Cycle Analysis and Coherence Analysis.
Steps:
   1. Download or Clone the Repo.
   2. Extract the  EdfXml.7z from Tests Directory to get sleep study EDF file (450002.EDF) and the annotation file (450002.EDF.XML) .
   3. Create a data source and analysis result folder. Place both the EDF file and the annotation file in the data source folder.
   4. Start Matlab. Start MATLAB. Set/navigate the current path to the source code folder or cloned repo directory.
   5. Start the Interface. Type 'SpectralTrainFig' at the command line or open SpectralTrainFig.mlapp which is updated one for small screens.
   6. Select data folder(Can create one in any path. This is the folder where you keep EDF/XML combination).
      Locate the 'Data Folder' text edit field. Select the data folder created by clicking on the elipses (...) to the right of the 'Data Folder text edit field.
   7. Select the result folder(Can create one in any path. This is the folder where results will be written).
      Locate the 'Results Folder' text edit field. Select the result folder created by clicking on the elipse (...) to the right of the 'Result Folder' text edit field.
   8. Start the analysis. Click on the button labeled 'Go(all)' which is located at the bottom of the graphical user interface.

### Parameters

##### Description
*Analysis Description*. Enter a brief analysis description.

*Output File Prefix*. Enter a prefix that will be used to start each file written by the program.

*Data Folder*. Select a folder containing EDF and XML files

*Results Folder*. Select a folder to write program generated files to.

##### Analysis Parameters
*Analysis Signals*. Enter signal labels that are to be analyzed as a cell string (ex. {'C3', 'C2', 'C3-A1'}. All of the EDF files opened during the analysis are expected to contain signals with the specified labels. Use your favorite EDF utility to determine the signal labels.  You can use [edfinfo](https://www.mathworks.com/help/signal/ref/edfinfo.html) to list the signal labels and to view the signals.

*Reference Signals*. Enter the labels of the reference signals as a cell string (ex. {'A1', 'M1', 'M2'}).

*Reference Methods*.  Select one of three approaches to referencing the signal.  
-  *Single reference signal*. Enter a single signal label as cell string (ex. {'M1'}).  The reference signal is subtracted from each analysis signal. Entering a null cell string is interpreted as not to reference the analysis signals (ex. {})). 
-  *Reference for each analysis signal*. Enter a reference for each signal as a cell string (ex. {'M1','M1','M2','M3'}). A signal label can be used multiple times.
-  *Average of reference signals*.  The average of the signals listed in the cell array is substracted from each analysis signals.

*Spectral Settings*
-    Default.  The default settings include a 10x4 second sub-epochs, a 50% [tukey window] (http://en.wikipedia.org/wiki/Window_function#Tukey_window) and a 30 second sleep staging scoring window.
-    SHHS.  The settings used for the [Sleep Heart Health Study](http://www.ncbi.nlm.nih.gov/pubmed/9493915) can be selected. The settings are 6x5 second sub-epochs, a [hanning window](http://en.wikipedia.org/wiki/Hann_function) and a 30 second sleep staging scoring window.

*ECG decontamination*. If selected, applies a template-subtraction method to remove the ECG artifact from all EEG leads.

*ECG channel name*. Enter the label of the ECG signal as a cell string (ex. {'ECG'}).

*Artifact Detection*
-    Delta (0.6-4.6 Hz). Set the multiplicative threshold for the delta band. The default value is 2.5.
-    Beta (40-60 Hz). Set the multiplicative thresold for the beta band. The defaults to 2.0.

*Monitor Id*. Select the monitor to display the figures created during processing.

*Start*. Select the file Id to start. The option is provided in order to trouble shoot a failed fun. Review the autogenerated file lists to identify files or review the error message.

##### GUI Function Button
*Close All*. Closes all open figures

*About*. Displays graphical user interface description and copyright notice.

*Set Bands*. Load an Excel file with a list of spectral bands to analyze/report on.  Examples of the Excel spreadsheet can be found in the release section. The spectral analysis band summaries include slow oscillations (0.5-1 Hz), delta (1-4 Hz), theta (4-8 Hz), alpha (8-12 Hz), sigma (12-15 Hz),  beta (15-30 Hz) and gamma (30-45). The default Excel file can be downloaded from [here](https://github.com/PaudelDhirendra/SleepStudy/blob/master/bandsettings/bandAnalysisSettings.xlsx).
 
*Bands*. Start batch processing. Compute and report band summaries by subject and create a summary across subjects.

*Go (min)*. Reccomended batch processing option.  Visual (PPT) and numeric (XLS) summaries are created across subjects.  Visual summary allows for a rapid review of all subjects.

*Go (all)*.  Detail visual (PPT) and numeric (XLS) summaries by subject and across subjects.

*Compute Coherence*. Select check box to compute coherence between each pair of analysis signals.  Warning: the number of signal pair increases rapidly as the number of analysis signals grow. 

*Sleep Cycle Analysis*. Select check box to compute sleep cycle analysis. 

### Technical Overview
The functional component of the GUI is implemented as a single [class](http://en.wikipedia.org/wiki/Object-oriented_programming). Most of the key components are written as classes. The class structure provides error checking and visual/numeric reporting capabilities and allows for the rapid development of a lean GUI. The use of PowerPoint and Excel as the standard ouput file type was selected so that research assistants with little programming experience can pre-screen large number of results. Many of the reccomendations for writing fast MATLAB script files are used in the program. The current time to process a single subject is currently 1 to 10 seconds on a medium size work station, depending on the number of outputs written to disk.  


#### MATLAB APP
The [MATLAB APP](http://www.mathworks.com/discovery/matlab-apps.html) is a great way to get started with sleep studies.

#### Requirements
Tested on MATLAB 2024a, the MATLAB's Signal Processing toolbox and the MATLAB's Statistics toolbox are required. Futhermore, for ECG decontamination and using smooth function Curve Fitting Toolbox is required. The [pwelch](http://www.mathworks.com/help/signal/ref/pwelch.html) function is used to compute  [EEG](http://en.wikipedia.org/wiki/Electroencephalography) spectra. The PPT generation functionality requires a MS Windows operating system. The memory and hard disk requirements are dependent on the size and number of sleep studies to be analyzed. The program can run on a laptop with 8 Gb of RAM.  The preferred configuration for a large number of studies is 16-32 Gb of RAM. Similarly, the required disk space is dependent on the number of signals processed, the number files selected and the number of ouputs generated by the program. 

#### Limitations
Using relatively simple artifact detection requires an explicit trade in spectral analysis quality (accuracy) and speed, when compared to manual artifact detection. The manual artifact detection approach does not include a muscle movement (EMG signal), loose lead analysis, EOG contamination analysis nor an ECG contamination analysis. NREM and REM frequency spectra for each subject are reviewed visually for non-physiological components and poor data in order to reduce the limitations of the implemented artifact detection approach. Despite these checks, we have observed that between 2-5% of subjects may have residual artifact that affects the frequency spectrum in the upper portions of the 15 to 25 Hz frequency range. Bland-Altman plots comparing band summaries from manual and automatic artifact detection approaches suggest that there is a small positive bias for the bands computed with the manual artifact detection approach (band computed with the automatic artifact detection being larger). Each investigator should assess whether the methods used in this application are appropriate for the research hypothesis under investigation.

#### Acknowledgments
Dozens of researchers, computer scientists, enginginners, technicians and research assistants assisted in the development of this program.

SleepStudy uses several utilities available from the MATLAB file exchange area including:
-    [SpectralTrainFig](https://www.mathworks.com/matlabcentral/fileexchange/49852-spectraltrainfig) & [source code](https://github.com/nsrr/SpectralTrainFig). The main app and source code from which this repo is forked.
-    [dirr](http://www.mathworks.com/matlabcentral/fileexchange/8682-dirr--find-files-recursively-filtering-name--date-or-bytes-) Used to create EDF/XMl file lists for processing
-    [moving](http://www.mathworks.com/matlabcentral/fileexchange/8251-moving-averages---moving-median-etc). Used to compute running band averages for the artifact detection computations.
-    [panel](http://www.mathworks.com/matlabcentral/fileexchange/20003-panel). Used to create a summary figure for review.
-    [saveppt2](http://www.mathworks.com/matlabcentral/fileexchange/19322-saveppt2). Used to create PPT summaries from MATLAB figures.


#### Related links
- [National Sleep Research Resource](https://sleepdata.org/)



