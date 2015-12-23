--Sessions control--
require("sessions-control-hammerspoon/sessions_control")

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "R", function()
	sessionsSave(sessions)
	hs.reload()
	sessionsToConfig(sessions)
	hs.notify.new({title="Hammerspoon", informativeText='Config loaded'}):send():release()
end)


