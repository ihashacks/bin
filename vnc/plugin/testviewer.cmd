REM ** Name this file testviewer.cmd

REM **********************************************
REM ** Turn on logging and start the viewer  
REM ** (for "NoReg" plugin troubleshooting)
REM **
REM ** When the viewer starts up, select the plugin, and then 
REM ** configure it or attempt a connection to create the logfile.
REM **
REM **********************************************


REM ** Set the working directory
REM ** change this to the correct directory for your setup!

set workingDirectory=c:\program files\UltraVNC

c:

cd "%workingDirectory%"

REM ** Set the keyfile

set msrc4pluginkey="%workingDirectory%\rc4.key"

REM ** Turn on the Plugin log

set dsmdebug=1

del rc4.log

REM ** Run the viewer with logging on

vncviewer -loglevel 9 -logfile vncviewer.log

REM ** The plugin logfile will be in the working directory and named rc4.log
REM ** The viewer log will be named vncviewer.log
REM ** Done
