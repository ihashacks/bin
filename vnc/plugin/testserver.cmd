REM ** Name this file testserver.cmd

REM *********************************************************
REM ** Turn on logging and start the server (as an application, NOT as a service)
REM ** (for "NoReg" plugin troubleshooting)
REM **
REM ** You will need to configure the Server Service to turn on logging 
REM ** (Log debug info checkbox) and then STOP the service!!!
REM **
REM ** After you run this you will see the tray icon appear.  Go ahead and configure the
REM ** plugin, or attempt to connect to the server to generate the plugin logfile.
REM **
REM ** Close the server when you are done testing. (Use the Icon in the system tray.)
REM ***********************************************************

REM ** Set the working directory
REM ** change this to the correct directory for your setup!

set workingDirectory=c:\program files\UltraVNC

c:

cd "%workingDirectory%"

REM ** Set the keyfile

set msrc4pluginkey="%workingDirectory%\rc4.key"

REM ** Turn on the Plugin log

set dsmdebug=1

REM ** Run the server

winvnc

REM ** The plugin logfile will be in the working directory and named rc4.log
REM ** The server log will be called WinVNC.log
REM ** Done
