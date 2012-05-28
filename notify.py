import os
 
#if DISPLAY is not set, then set it to default ':0.0'
if len( os.getenv( 'DISPLAY', '' ) ) == 0:
	os.putenv( 'DISPLAY', ':0.0' )
 
import pygtk
pygtk.require("2.0")
import gtk
import threading
import time
 
#GTK main loop thread
class GTKMainThread(threading.Thread):
	def run(self):
		gtk.main()
 
#get default display. None means it can't connect to xserver
display = gtk.gdk.display_get_default()
statusIcon =  None
 
#if the display is not None show status icon
if not display is None:
	#start a gtk loop in another thread
	gtk.gdk.threads_init()
	GTKMainThread().start()
 
	try:
		statusIcon = gtk.StatusIcon()
		statusIcon.set_from_stock( gtk.STOCK_INFO )
		statusIcon.set_visible( True )
		statusIcon.set_tooltip(_("Back In Time: take snapshot ..."))
	except:
		pass
 
#do something here
print "Begin"
time.sleep( 5 ) #wait 5 seconds
print "End"
 
#hide status icon
if not statusIcon is None:
	statusIcon.set_visible( False )
 
#quit GTK main look
if not display is None:
	gtk.main_quit()
