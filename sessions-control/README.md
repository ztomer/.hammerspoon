# sessions control for hammerspoon
A script for hammerspoon(Mac) that can switch among sessions

# Description
Use a set of hotkeys to control some sessions which is a set of windows.

You can easily minimize all windows of a session, and unminimize the another one.
We will also save the full screen status, will set window full screen if it was.

For now, we only minimize the windows, and will update to hide the windows not in work.

# Features
* Create sessions in sav file
* Add windows to current sessions
* Switching among sessions
	* Switch to next or previous one
	* Switch by number
* Auto save and load the sessions
* Add and delete sessions by editing cfg file.

# ToDo:
* show windows in current session

# MayBe:
* Change session to a table like

	{{win, isFull}, {...}, name=name_of_session}

	and use ipairs to find window

* Hide icon in dock that is not in current session

# Contact
Author: PapEr (zw.paper@gmail.com)

# License
The MIT License (MIT)
